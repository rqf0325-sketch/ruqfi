--[[
	Chunk-level fixes for Roblox binary model files (.rbxm), applied around
	Lune's own (de)serializer.

	  rbxm.cleanForLune(data)      strips what Lune can't read yet
	  rbxm.legacyContent(data)     rewrites Content-typed mesh/texture
	                               properties as the plain strings Studio
	                               itself saves

	Chunks are written back uncompressed (compressed length 0), which the
	format allows and Studio reads.
]]

local rbxm = {}

-- LZ4 block format (what .rbxm chunks use; Lune's serde only does LZ4 frames).
local function lz4Block(src: buffer, size: number): buffer
	local out = buffer.create(size)
	local ip, op, n = 0, 0, buffer.len(src)
	while ip < n do
		local token = buffer.readu8(src, ip)
		ip += 1
		local literals = bit32.rshift(token, 4)
		if literals == 15 then
			repeat
				local extra = buffer.readu8(src, ip)
				ip += 1
				literals += extra
			until extra ~= 255
		end
		buffer.copy(out, op, src, ip, literals)
		ip += literals
		op += literals
		if ip >= n then
			break
		end
		local offset = buffer.readu16(src, ip)
		ip += 2
		local length = bit32.band(token, 15)
		if length == 15 then
			repeat
				local extra = buffer.readu8(src, ip)
				ip += 1
				length += extra
			until extra ~= 255
		end
		length += 4
		-- Byte by byte: a match may overlap the bytes it is producing.
		for i = 0, length - 1 do
			buffer.writeu8(out, op + i, buffer.readu8(out, op - offset + i))
		end
		op += length
	end
	assert(op == size, `LZ4: expected {size} bytes, got {op}`)
	return out
end

type Chunk = { name: string, data: buffer }

local function readChunks(data: string): (string, { Chunk })
	local b = buffer.fromstring(data)
	assert(buffer.readstring(b, 0, 8) == "<roblox!", "not a binary Roblox model")
	local header = buffer.readstring(b, 0, 32)
	local chunks = {}
	local pos = 32
	while pos < buffer.len(b) do
		local name = buffer.readstring(b, pos, 4)
		local compressed = buffer.readu32(b, pos + 4)
		local size = buffer.readu32(b, pos + 8)
		pos += 16
		local body
		if compressed == 0 then
			body = buffer.create(size)
			buffer.copy(body, 0, b, pos, size)
			pos += size
		else
			local raw = buffer.create(compressed)
			buffer.copy(raw, 0, b, pos, compressed)
			pos += compressed
			assert(buffer.readu32(raw, 0) ~= 0xFD2FB528, "zstd-compressed chunks are not supported")
			body = lz4Block(raw, size)
		end
		table.insert(chunks, { name = name, data = body })
		if name == "END\0" then
			break
		end
	end
	return header, chunks
end

local function writeChunks(header: string, chunks: { Chunk }): string
	local parts = { header }
	for _, chunk in chunks do
		local head = buffer.create(16)
		buffer.writestring(head, 0, chunk.name)
		buffer.writeu32(head, 4, 0)
		buffer.writeu32(head, 8, buffer.len(chunk.data))
		buffer.writeu32(head, 12, 0)
		table.insert(parts, buffer.tostring(head))
		table.insert(parts, buffer.tostring(chunk.data))
	end
	return table.concat(parts)
end

local function readString(b: buffer, pos: number): (string, number)
	local length = buffer.readu32(b, pos)
	return buffer.readstring(b, pos + 4, length), pos + 4 + length
end

-- PROP chunk: class id (u32), property name, type byte, values.
local function propInfo(chunk: Chunk): (number, string, number, number)
	local class = buffer.readu32(chunk.data, 0)
	local name, pos = readString(chunk.data, 4)
	return class, name, buffer.readu8(chunk.data, pos), pos + 1
end

-- INST chunks: class id -> class name, instance count.
local function classes(chunks: { Chunk }): { [number]: { name: string, count: number } }
	local result = {}
	for _, chunk in chunks do
		if chunk.name == "INST" then
			local id = buffer.readu32(chunk.data, 0)
			local name, pos = readString(chunk.data, 4)
			result[id] = { name = name, count = buffer.readu32(chunk.data, pos + 1) }
		end
	end
	return result
end

local SHARED_STRING = 0x1C
local STRING = 0x01
local CONTENT = 0x22

-- Newer Studio versions save Tags as a SharedString, which Lune rejects
-- ("Property Tags should be SharedString, but it was Tags"). Tags are
-- dropped; returns the cleaned file and how many non-empty tag lists were lost.
function rbxm.cleanForLune(data: string): (string, number)
	local header, chunks = readChunks(data)
	local kept, lost = {}, 0
	for _, chunk in chunks do
		if chunk.name == "PROP" then
			local _, name, kind, pos = propInfo(chunk)
			if name == "Tags" and kind == SHARED_STRING then
				-- Values are interleaved big-endian u32 indices into SSTR; index 0 is the empty string in every file seen so far.
				for i = pos, buffer.len(chunk.data) - 1 do
					if buffer.readu8(chunk.data, i) ~= 0 then
						lost += 1
						break
					end
				end
				continue
			end
		end
		table.insert(kept, chunk)
	end
	return writeChunks(header, kept), lost
end

-- Content property -> the string property Studio saves for it.
local LEGACY_NAMES = {
	MeshPart = { MeshContent = "MeshId", TextureContent = "TextureID" },
	SpecialMesh = { MeshContent = "MeshId", TextureContent = "TextureId" },
	Decal = { TextureContent = "Texture" },
	Texture = { TextureContent = "Texture" },
}

-- Newer Lune versions save MeshId/TextureID as Content-typed "MeshContent"
-- /"TextureContent". Studio itself saves the old string properties, so write
-- those instead. Only plain URIs are supported (no object references).
function rbxm.legacyContent(data: string): (string, number)
	local header, chunks = readChunks(data)
	local classList = classes(chunks)
	local converted = 0
	for _, chunk in chunks do
		if chunk.name ~= "PROP" then
			continue
		end
		local classId, name, kind, pos = propInfo(chunk)
		local class = classList[classId]
		local legacy = LEGACY_NAMES[class.name] and LEGACY_NAMES[class.name][name]
		if kind ~= CONTENT or not legacy then
			continue
		end
		local b, count = chunk.data, class.count
		-- Source types: interleaved big-endian i32, zigzag encoded. 0 = none, 1 = URI.
		local sources = table.create(count)
		for i = 0, count - 1 do
			local raw = bit32.bor(
				bit32.lshift(buffer.readu8(b, pos + i), 24),
				bit32.lshift(buffer.readu8(b, pos + count + i), 16),
				bit32.lshift(buffer.readu8(b, pos + 2 * count + i), 8),
				buffer.readu8(b, pos + 3 * count + i)
			)
			local value = bit32.bxor(bit32.rshift(raw, 1), -bit32.band(raw, 1))
			assert(value == 0 or value == 1, `{class.name}.{name}: only empty or URI content is supported`)
			sources[i + 1] = value
		end
		pos += 4 * count
		local uriCount = buffer.readu32(b, pos)
		pos += 4
		local uris = {}
		for _ = 1, uriCount do
			local uri
			uri, pos = readString(b, pos)
			table.insert(uris, uri)
		end
		assert(buffer.readu32(b, pos) == 0, `{class.name}.{name}: object references are not supported`)

		local head = buffer.create(4)
		buffer.writeu32(head, 0, classId)
		local nameLength = buffer.create(4)
		buffer.writeu32(nameLength, 0, #legacy)
		local out = { buffer.tostring(head), buffer.tostring(nameLength), legacy, string.char(STRING) }
		local nextUri = 1
		for i = 1, count do
			local value = ""
			if sources[i] == 1 then
				value = uris[nextUri]
				nextUri += 1
			end
			local length = buffer.create(4)
			buffer.writeu32(length, 0, #value)
			table.insert(out, buffer.tostring(length))
			table.insert(out, value)
		end
		chunk.data = buffer.fromstring(table.concat(out))
		converted += 1
	end
	return writeChunks(header, chunks), converted
end

-- Property name -> type byte for one class, for checks.
function rbxm.propertyTypes(data: string, className: string): { [string]: number }
	local _, chunks = readChunks(data)
	local classList = classes(chunks)
	local result = {}
	for _, chunk in chunks do
		if chunk.name == "PROP" then
			local classId, name, kind = propInfo(chunk)
			if classList[classId].name == className then
				result[name] = kind
			end
		end
	end
	return result
end

return rbxm
