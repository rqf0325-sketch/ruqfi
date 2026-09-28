// Renders preview images of the scooter: every colour theme, the rider's
// poses (R6 and R15) and a night shot with the lights on.
//
//   lune run tools/build-scooter.luau -- --dump
//   lune run tools/test-scooter-pose.luau -- --dump
//   node tools/preview/scooter.cjs
//
// Needs Playwright and three@0.149 (npm install --no-save three@0.149.0 playwright);
// CHROMIUM=/path/to/chrome to use an already installed browser.
// The meshes themselves are Roblox assets that can't be downloaded here, so
// every part is drawn as a simple shape (box, tube, wheel) of the same size,
// place and colour: good for colours and poses, not for mesh detail.
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const ROOT = path.resolve(__dirname, "../..");
const THREE_PATH = path.join(ROOT, "node_modules/three/build/three.min.js");
const scooter = JSON.parse(fs.readFileSync(path.join(ROOT, "build/scooter.json"), "utf8"));
const poses = JSON.parse(fs.readFileSync(path.join(ROOT, "build/scooter-poses.json"), "utf8"));

const SHOTS = [
	{ file: "docs/scooter-themes.png", width: 1600, height: 820, kind: "themes" },
	{ file: "docs/scooter-rider.png", width: 1750, height: 820, kind: "poses" },
	{ file: "docs/scooter-night.png", width: 1200, height: 675, kind: "night" },
];

// Runs in the page.
function render({ data, shot }) {
	const { scooter, poses } = data;
	const width = shot.width, height = shot.height;
	document.body.style.cssText = "margin:0;background:#0b0e16;font-family:'DejaVu Sans',Arial,sans-serif";
	const stage = document.createElement("div");
	stage.style.cssText = `position:relative;width:${width}px;height:${height}px;overflow:hidden`;
	document.body.appendChild(stage);
	const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
	renderer.setSize(width, height);
	renderer.setPixelRatio(1);
	renderer.shadowMap.enabled = true;
	renderer.shadowMap.type = THREE.PCFSoftShadowMap;
	renderer.outputEncoding = THREE.sRGBEncoding;
	renderer.setScissorTest(true);
	stage.appendChild(renderer.domElement);

	const cf = (c) => {
		const m = new THREE.Matrix4();
		m.set(c[3], c[4], c[5], c[0], c[6], c[7], c[8], c[1], c[9], c[10], c[11], c[2], 0, 0, 0, 1);
		return m;
	};
	const byName = {};
	for (const p of scooter.parts) byName[p.group + "/" + p.name] = p;
	const hubOf = { Chassis: "Root", Steering: "SteerHub", FrontWheel: "FrontHub", RearWheel: "RearHub" };
	const hubPart = (name) => scooter.parts.find((p) => p.name === name);

	function material(look, night) {
		const color = new THREE.Color(look.color[0], look.color[1], look.color[2]).convertSRGBToLinear();
		const m = new THREE.MeshStandardMaterial({ color });
		switch (look.material) {
			case "Neon":
				m.emissive = color.clone();
				m.emissiveIntensity = night ? 1.6 : 0.9;
				m.roughness = 0.4;
				break;
			case "Metal":
				m.metalness = 0.75;
				m.roughness = 0.38;
				break;
			case "Foil":
				m.metalness = 1;
				m.roughness = 0.18;
				break;
			case "Asphalt":
			case "Sand":
				m.roughness = 1;
				break;
			case "Rubber":
				m.roughness = 0.92;
				break;
			case "Plastic":
				m.roughness = 0.75;
				break;
			default:
				m.roughness = 0.3 - (look.reflectance || 0);
		}
		return m;
	}

	function cylinderBetween(a, b, radius, mat) {
		const dir = new THREE.Vector3().subVectors(b, a);
		const geo = new THREE.CylinderGeometry(radius, radius, dir.length(), 20);
		const mesh = new THREE.Mesh(geo, mat);
		mesh.position.copy(a).add(b).multiplyScalar(0.5);
		mesh.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir.clone().normalize());
		return mesh;
	}

	// One scooter part as a simple shape, in the part's own space.
	function partShape(p, mat) {
		const [sx, sy, sz] = p.size;
		const V = (x, y, z) => new THREE.Vector3(x, y, z);
		const n = p.name;
		if (n === "Tire") {
			const R = sy / 2, r = Math.min(sz / 2, R * 0.3);
			const mesh = new THREE.Mesh(new THREE.TorusGeometry(R - r, r, 16, 40), mat);
			mesh.scale.z = sz / (2 * r);
			return mesh;
		}
		if (n === "Column" || n === "HeadTube") {
			const r = sz / 2 * (n === "HeadTube" ? 1.25 : 1);
			return cylinderBetween(V(sx / 2 - r, -sy / 2, 0), V(-sx / 2 + r, sy / 2, 0), r, mat);
		}
		if (n === "ForkLeft" || n === "ForkRight") {
			const t = sz / 2;
			return cylinderBetween(V(-sx / 2 + t, sy / 2 - t, 0), V(sx / 2 - t, -sy / 2 + t, 0), t, mat);
		}
		if (n === "RearForkLeft" || n === "RearForkRight") {
			const t = sz / 2;
			return cylinderBetween(V(sx / 2 - t, sy / 2 - t, 0), V(-sx / 2 + t, -sy / 2 + t, 0), t, mat);
		}
		if (["Handlebar", "GripLeft", "GripRight", "FrontAxle", "RearAxle", "FenderPivot", "BarClamp", "HingeBoltLeft", "HingeBoltRight"].includes(n)) {
			const r = Math.min(sx, sy) / 2 * (n.startsWith("Grip") ? 1.15 : 1);
			return cylinderBetween(V(0, 0, -sz / 2), V(0, 0, sz / 2), r, mat);
		}
		if (n.startsWith("Bolt")) {
			return cylinderBetween(V(0, -sy / 2, 0), V(0, sy / 2, 0), Math.min(sx, sz) / 2, mat);
		}
		if (n === "RearFender") {
			const R = sx / 2, t = 0.05;
			const cy = sy / 2 - R;
			const low = Math.asin(Math.max(-1, Math.min(1, (sy / 2 - sy - cy) / R)));
			const shape = new THREE.Shape();
			shape.absarc(0, 0, R, low, Math.PI - low, false);
			shape.absarc(0, 0, R - t, Math.PI - low, low, true);
			const geo = new THREE.ExtrudeGeometry(shape, { depth: sz, bevelEnabled: false, curveSegments: 32 });
			geo.translate(0, cy, -sz / 2);
			return new THREE.Mesh(geo, mat);
		}
		if (n === "Headlamp") {
			return cylinderBetween(V(-sx / 2, 0, 0), V(sx / 2, 0, 0), sy / 2, mat);
		}
		return new THREE.Mesh(new THREE.BoxGeometry(sx, sy, sz), mat);
	}

	// The scooter as nested groups: Root -> SteerHub -> FrontHub, Root -> RearHub.
	function buildScooter(themeName, pose, night) {
		const theme = scooter.themes[themeName];
		const hubs = {};
		for (const name of ["Root", "SteerHub", "FrontHub", "RearHub"]) {
			const g = new THREE.Group();
			g.matrixAutoUpdate = false;
			hubs[name] = g;
		}
		const file = (name) => cf(hubPart(name).cframe);
		const inv = (m) => m.clone().invert();
		const steerC0 = inv(file("Root")).multiply(file("SteerHub"));
		const frontC0 = inv(file("SteerHub")).multiply(file("FrontHub"));
		const rearC0 = inv(file("Root")).multiply(file("RearHub"));
		const steerT = pose ? cf(pose.steer) : new THREE.Matrix4();
		const wheelT = pose ? cf(pose.wheel) : new THREE.Matrix4();
		hubs.Root.matrix.copy(pose ? cf(pose.root) : file("Root"));
		hubs.SteerHub.matrix.copy(steerC0.clone().multiply(steerT));
		hubs.FrontHub.matrix.copy(frontC0.clone().multiply(wheelT));
		hubs.RearHub.matrix.copy(rearC0.clone().multiply(wheelT));
		hubs.Root.add(hubs.SteerHub, hubs.RearHub);
		hubs.SteerHub.add(hubs.FrontHub);

		for (const p of scooter.parts) {
			if (!p.role) continue;
			const hubName = hubOf[p.group];
			let look = theme[p.role];
			if (p.role === "Original") {
				// Keeps its own texture in the game (can't be shown here): drawn in its base colour.
				look = { color: p.color, material: "Plastic" };
			} else if (p.role === "Lamp") {
				look = { color: [0.92, 0.92, 0.89], material: night ? "Neon" : "SmoothPlastic", reflectance: 0.2 };
			}
			const mat = material(look, night);
			if (p.name.startsWith("Spoke")) continue; // drawn per wheel below
			const mesh = partShape(p, mat);
			const holder = new THREE.Group();
			holder.matrixAutoUpdate = false;
			holder.matrix.copy(inv(file(hubName)).multiply(cf(p.cframe)));
			holder.add(mesh);
			mesh.castShadow = true;
			mesh.receiveShadow = true;
			hubs[hubName].add(holder);
		}
		// Wheels: rim ring, hub and five spokes in the rim colour.
		for (const [group, hubName] of [["FrontWheel", "FrontHub"], ["RearWheel", "RearHub"]]) {
			const tire = byName[group + "/Tire"];
			const R = tire.size[1] / 2 * 0.72;
			const w = tire.size[2] * 0.7;
			const mat = material(theme.Rim, night);
			const rim = new THREE.Mesh(new THREE.TorusGeometry(R, 0.035, 10, 40), mat);
			rim.rotation.y = Math.PI / 2;
			rim.scale.z = w / 0.07;
			hubs[hubName].add(rim);
			hubs[hubName].add(cylinderBetween(new THREE.Vector3(-w / 2, 0, 0), new THREE.Vector3(w / 2, 0, 0), 0.07, mat));
			for (let i = 0; i < 5; i++) {
				const a = (i / 5) * Math.PI * 2;
				const spoke = new THREE.Mesh(new THREE.BoxGeometry(w * 0.8, 0.05, R), mat);
				spoke.position.set(0, Math.cos(a) * R / 2, Math.sin(a) * R / 2);
				spoke.rotation.x = -a;
				hubs[hubName].add(spoke);
			}
		}
		return hubs.Root;
	}

	const srgb = (hex) => new THREE.Color(hex).convertSRGBToLinear();
	const SKIN = srgb("#e8b98f"), SHIRT = srgb("#3e72d6"), PANTS = srgb("#2b2f3a");
	function partColor(name) {
		if (/Head|Arm|Hand|LowerArm/.test(name)) return /Upper/.test(name) ? SHIRT : SKIN;
		if (/Torso/.test(name)) return name === "LowerTorso" ? PANTS : SHIRT;
		return PANTS;
	}
	function buildRider(pose) {
		const group = new THREE.Group();
		for (const b of pose.body) {
			const mat = new THREE.MeshStandardMaterial({ color: partColor(b.name), roughness: 0.65 });
			let mesh;
			if (b.name === "Head") {
				mesh = new THREE.Mesh(new THREE.CylinderGeometry(0.62, 0.62, 1.2, 28), mat);
				const face = new THREE.MeshBasicMaterial({ color: 0x111111 });
				for (const x of [-0.22, 0.22]) {
					const eye = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.18, 0.02), face);
					eye.position.set(x, 0.1, -0.62);
					mesh.add(eye);
				}
				const mouth = new THREE.Mesh(new THREE.BoxGeometry(0.36, 0.06, 0.02), face);
				mouth.position.set(0, -0.2, -0.61);
				mesh.add(mouth);
			} else {
				mesh = new THREE.Mesh(new THREE.BoxGeometry(b.size[0] * 0.98, b.size[1] * 0.98, b.size[2] * 0.98), mat);
			}
			const holder = new THREE.Group();
			holder.matrixAutoUpdate = false;
			holder.matrix.copy(cf(b.cframe));
			holder.add(mesh);
			mesh.castShadow = true;
			group.add(holder);
		}
		return group;
	}

	function world(night) {
		const scene = new THREE.Scene();
		scene.background = new THREE.Color(night ? "#0b0e16" : "#e9edf3").convertSRGBToLinear();
		const ground = new THREE.Mesh(
			new THREE.PlaneGeometry(200, 200),
			new THREE.MeshStandardMaterial({ color: new THREE.Color(night ? "#1d2027" : "#c9ced8").convertSRGBToLinear(), roughness: 0.95 })
		);
		ground.rotation.x = -Math.PI / 2;
		ground.receiveShadow = true;
		scene.add(ground);
		scene.add(new THREE.HemisphereLight(night ? 0x2a3350 : 0xf2f6ff, night ? 0x0b0c10 : 0x9098a6, night ? 0.35 : 0.85));
		const sun = new THREE.DirectionalLight(night ? 0x8fa4ff : 0xffffff, night ? 0.35 : 1.35);
		sun.position.set(-6, 12, -4);
		sun.castShadow = true;
		sun.shadow.mapSize.set(2048, 2048);
		Object.assign(sun.shadow.camera, { left: -8, right: 8, top: 8, bottom: -8 });
		scene.add(sun);
		return scene;
	}

	// Poses are recorded wherever the test ride was: bring them back to the origin.
	function place(object, origin) {
		const g = new THREE.Group();
		g.matrixAutoUpdate = false;
		g.matrix.copy(cf(origin).invert());
		g.add(object);
		return g;
	}

	const labels = [];
	function label(text, x, y, color, size) {
		const div = document.createElement("div");
		div.textContent = text;
		div.style.cssText = `position:absolute;left:${x}px;top:${y}px;color:${color};font-size:${size}px;font-weight:700;letter-spacing:0.06em`;
		stage.appendChild(div);
		labels.push(div);
	}

	function panel(scene, camera, x, y, w, h) {
		renderer.setViewport(x, height - y - h, w, h);
		renderer.setScissor(x, height - y - h, w, h);
		camera.aspect = w / h;
		camera.updateProjectionMatrix();
		renderer.render(scene, camera);
	}

	if (shot.kind === "themes") {
		const cols = 4, rows = 2, w = width / cols, h = height / rows;
		scooter.themeOrder.forEach((name, i) => {
			const scene = world(false);
			scene.add(buildScooter(name, null, false));
			const camera = new THREE.PerspectiveCamera(30, w / h, 0.1, 100);
			camera.position.set(7.4, 3.5, -5.6);
			camera.lookAt(0, 1.6, -0.3);
			const x = (i % cols) * w, y = Math.floor(i / cols) * h;
			panel(scene, camera, x, y, w, h);
			label(name.toUpperCase() + (i === 0 ? "  (bawaan)" : ""), x + 22, y + 16, "#1d2230", 18);
		});
	} else if (shot.kind === "poses") {
		const names = ["standing", "kick-push", "kick-return", "cruising", "turning", "tailwhip", "spin"];
		const titles = {
			standing: "BERHENTI", "kick-push": "TENDANG", "kick-return": "TENDANG (ANGKAT)", cruising: "MELUNCUR",
			turning: "BELOK", tailwhip: "TAILWHIP", spin: "SPIN 360",
		};
		const w = width / names.length, h = height / 2;
		["R6", "R15"].forEach((rig, row) => {
			names.forEach((name, i) => {
				const pose = poses.find((p) => p.rig === rig && p.label === name);
				const scene = world(false);
				const group = new THREE.Group();
				group.add(buildScooter("Noctis", pose, false));
				group.add(buildRider(pose));
				scene.add(place(group, pose.origin));
				const camera = new THREE.PerspectiveCamera(30, w / h, 0.1, 100);
				camera.position.set(13.5, 4.6, -4.2);
				camera.lookAt(0, 2.5, -0.3);
				const x = i * w, y = row * h;
				panel(scene, camera, x, y, w, h);
				label(`${rig} · ${titles[name]}`, x + 14, y + 12, "#1d2230", 13);
			});
		});
	} else {
		const scene = world(true);
		const pose = poses.find((p) => p.rig === "R6" && p.label === "cruising");
		const group = new THREE.Group();
		const bike = buildScooter("Noctis", pose, true);
		group.add(bike);
		group.add(buildRider(pose));
		scene.add(place(group, pose.origin));
		const glowColor = new THREE.Color(...scooter.themes.Noctis.Glow.color).convertSRGBToLinear();
		const glow = new THREE.PointLight(glowColor, 2.2, 7, 2);
		glow.position.set(0, 0.25, -0.2);
		scene.add(glow);
		const beam = new THREE.SpotLight(0xfff4d6, 2.2, 30, Math.PI / 6, 0.5, 1);
		beam.position.set(0, 2.9, -1.3);
		beam.target.position.set(0, 0, -12);
		scene.add(beam, beam.target);
		const camera = new THREE.PerspectiveCamera(30, width / height, 0.1, 100);
		camera.position.set(14, 6.5, -19);
		camera.lookAt(-0.5, 1.2, -4.5);
		panel(scene, camera, 0, 0, width, height);
		label("NOCTIS · MALAM (lampu depan + underglow menyala otomatis)", 24, height - 44, "#e8ecf5", 18);
	}
}

(async () => {
	// CHROMIUM=/path/to/chrome uses an existing browser instead of Playwright's own.
	const browser = await chromium.launch({
		executablePath: process.env.CHROMIUM || undefined,
		args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader"],
	});
	const page = await browser.newPage();
	for (const shot of SHOTS) {
		await page.setViewportSize({ width: shot.width, height: shot.height });
		await page.setContent("<!doctype html><html><body></body></html>");
		await page.addScriptTag({ path: THREE_PATH });
		await page.evaluate(render, { data: { scooter, poses }, shot });
		await page.screenshot({ path: path.join(ROOT, shot.file) });
		console.log(`Wrote ${shot.file}`);
	}
	await browser.close();
})();
