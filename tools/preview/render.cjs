// Renders build/tree.json (from `lune run tools/build.luau -- --tree`) to PNG
// screenshots, approximating how Roblox lays the GUI out.
//
//   node tools/preview/render.cjs             all screenshots
//   node tools/preview/render.cjs playermenu  only the ones whose file name contains "playermenu"
//
// Needs Playwright and Montserrat woff2 files in build/fonts (npm pack @fontsource/montserrat).
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const ROOT = path.resolve(__dirname, "../..");
const FONT_DIR = path.join(ROOT, "build/fonts/package/files");
const readTree = (file) => JSON.parse(fs.readFileSync(path.join(ROOT, file), "utf8"));

// build/tree.json: `lune run tools/build.luau -- --tree`
// build/touch-tree.json: `lune run tools/patch-road-glide.luau -- --tree`
// build/pm-*.json: `lune run tools/build-player-menu.luau -- --tree`
const SHOTS = [
	{ tree: "build/tree.json", file: "docs/preview-desktop.png", width: 1280, height: 720 },
	{ tree: "build/tree.json", file: "docs/preview-phone.png", width: 844, height: 390 },
	{ tree: "build/touch-tree.json", file: "docs/preview-touch.png", width: 844, height: 390 },
	{ tree: "build/pm-desktop.json", file: "docs/playermenu-desktop.png", width: 960, height: 540, scene: "tiles" },
	{ tree: "build/pm-plain.json", file: "docs/playermenu-plain.png", width: 960, height: 540, scene: "tiles" },
	{ tree: "build/pm-phone.json", file: "docs/playermenu-phone.png", width: 844, height: 390, scene: "tiles" },
	{ tree: "build/pm-hud.json", file: "docs/playermenu-hud.png", width: 960, height: 540, scene: "tiles" },
	{ tree: "build/pm-profile.json", file: "docs/playermenu-profile.png", width: 384, height: 560, scene: "tiles" },
	{ tree: "build/pm-chat.json", file: "docs/playermenu-chat.png", width: 384, height: 560, scene: "tiles" },
	{ tree: "build/pm-nametag.json", file: "docs/playermenu-nametag.png", width: 760, height: 130 },
];

const fontFaces = [400, 500, 600, 700, 800]
	.map((weight) => {
		const file = path.join(FONT_DIR, `montserrat-latin-${weight}-normal.woff2`);
		return `@font-face{font-family:Montserrat;font-weight:${weight};src:url(file://${file}) format("woff2");}`;
	})
	.join("\n");

// Runs in the page.
function renderGui(tree) {
	const GUI = new Set(["Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame"]);
	const kids = (n) => (Array.isArray(n.children) ? n.children : []);
	const kid = (n, cls) => kids(n).find((c) => c.class === cls);
	const rgba = (c, t) => `rgba(${Math.round(c.r * 255)},${Math.round(c.g * 255)},${Math.round(c.b * 255)},${(1 - t).toFixed(3)})`;
	const texts = [];
	const TEXT = ["TextLabel", "TextButton", "TextBox"];
	const gradientOf = (n) => {
		const g = kid(n, "UIGradient");
		return g && g.props.Enabled !== false ? g : undefined;
	};

	function sample(points, t, key) {
		for (let i = 0; i < points.length - 1; i++) {
			const a = points[i], b = points[i + 1];
			if (t >= a.t && t <= b.t) {
				const f = b.t === a.t ? 0 : (t - a.t) / (b.t - a.t);
				return key.map((k) => a[k] + (b[k] - a[k]) * f);
			}
		}
		return key.map((k) => points[points.length - 1][k]);
	}

	function background(p, grad) {
		const base = p.BackgroundColor3, bgT = p.BackgroundTransparency;
		if (!grad) return rgba(base, bgT);
		const cs = grad.props.Color, ts = grad.props.Transparency;
		const times = [...new Set([...cs.map((k) => k.t), ...ts.map((k) => k.t)])].sort((a, b) => a - b);
		const stops = times.map((t) => {
			const [r, g, b] = sample(cs, t, ["r", "g", "b"]);
			const [tr] = sample(ts, t, ["v"]);
			const alpha = 1 - (1 - bgT) * (1 - tr);
			return `${rgba({ r: r * base.r, g: g * base.g, b: b * base.b }, alpha)} ${t * 100}%`;
		});
		return `linear-gradient(${90 + grad.props.Rotation}deg, ${stops.join(", ")})`;
	}

	function sizeOf(n, pw, ph) {
		const s = n.props.Size;
		let w = s.xs * pw + s.xo, h = s.ys * ph + s.yo;
		const ar = kid(n, "UIAspectRatioConstraint");
		if (ar) {
			const r = ar.props.AspectRatio;
			if (ar.props.AspectType === "FitWithinMaxSize") {
				if (w / h > r) w = h * r;
				else h = w / r;
			} else if (ar.props.DominantAxis === "Width") h = w / r;
			else w = h * r;
		}
		return [w, h];
	}

	function render(n, parentEl, pw, ph, forced) {
		const p = n.props;
		if (p.Visible === false) return;
		let [w, h] = forced ? [forced.w, forced.h] : sizeOf(n, pw, ph);
		let x, y;
		if (forced && forced.x != null) [x, y] = [forced.x, forced.y];
		else {
			x = p.Position.xs * pw + p.Position.xo - p.AnchorPoint.x * w;
			y = p.Position.ys * ph + p.Position.yo - p.AnchorPoint.y * h;
		}

		const el = document.createElement("div");
		el.dataset.name = p.Name;
		Object.assign(el.style, {
			position: "absolute", left: `${x}px`, top: `${y}px`, width: `${w}px`, height: `${h}px`,
			zIndex: String(p.ZIndex ?? 1),
		});
		const uiScale = kid(n, "UIScale");
		const transforms = [];
		if (uiScale && uiScale.props.Scale !== 1) {
			transforms.push(`scale(${uiScale.props.Scale})`);
			el.style.transformOrigin = `${p.AnchorPoint.x * 100}% ${p.AnchorPoint.y * 100}%`;
		}
		if (p.Rotation && GUI.has(n.class)) transforms.push(`rotate(${p.Rotation}deg)`);
		if (transforms.length) el.style.transform = transforms.join(" ");
		if (p.BackgroundTransparency < 1) el.style.background = background(p, gradientOf(n));
		const corner = kid(n, "UICorner");
		if (corner) el.style.borderRadius = `${corner.props.CornerRadius.s * Math.min(w, h) + corner.props.CornerRadius.o}px`;
		const stroke = kid(n, "UIStroke");
		// Contextual strokes outline the text of a TextLabel; Border strokes outline the box.
		const textStroke = stroke && TEXT.includes(n.class) && stroke.props.ApplyStrokeMode === "Contextual";
		if (stroke && stroke.props.Enabled !== false && !textStroke) el.style.boxShadow = `0 0 0 ${stroke.props.Thickness}px ${rgba(stroke.props.Color, stroke.props.Transparency)}`;
		if (n.class === "ImageLabel" && typeof p.Image === "string" && p.Image.startsWith("preview:")) {
			// Sample pictures for the previews live in tools/preview (Roblox images are not fetched).
			Object.assign(el.style, {
				backgroundImage: `url("file://${tree.previewDir}/${p.Image.slice(8)}")`,
				backgroundSize: p.ScaleType === "Fit" ? "contain" : "cover",
				backgroundPosition: "center",
				backgroundRepeat: "no-repeat",
				opacity: String(1 - (p.ImageTransparency ?? 0)),
			});
		}
		if (p.ClipsDescendants || n.class === "ScrollingFrame") el.style.overflow = "hidden";
		parentEl.appendChild(el);

		const pad = kid(n, "UIPadding");
		const padOf = (u, size) => (u ? u.s * size + u.o : 0);
		const pl = padOf(pad?.props.PaddingLeft, w), pr = padOf(pad?.props.PaddingRight, w);
		const pt = padOf(pad?.props.PaddingTop, h), pb = padOf(pad?.props.PaddingBottom, h);
		const cw = w - pl - pr, ch = h - pt - pb;

		if (["TextLabel", "TextButton", "TextBox"].includes(n.class)) {
			let text = p.Text, color = p.TextColor3;
			if (n.class === "TextBox" && !text) [text, color] = [p.PlaceholderText, p.PlaceholderColor3];
			if (text) {
				const box = document.createElement("div");
				Object.assign(box.style, {
					position: "absolute", left: `${pl}px`, top: `${pt}px`, width: `${cw}px`, height: `${ch}px`,
					display: "flex",
					justifyContent: { Left: "flex-start", Center: "center", Right: "flex-end" }[p.TextXAlignment],
					alignItems: { Top: "flex-start", Center: "center", Bottom: "flex-end" }[p.TextYAlignment],
				});
				const span = document.createElement("span");
				Object.assign(span.style, {
					whiteSpace: "pre", lineHeight: "1", fontFamily: "Montserrat, 'Noto Color Emoji'",
					fontWeight: String(p.FontFace.weight), color: rgba(color, p.TextTransparency ?? 0),
				});
				if (textStroke) {
					const t = stroke.props.Thickness, c = rgba(stroke.props.Color, stroke.props.Transparency);
					span.style.textShadow = [[t, 0], [-t, 0], [0, t], [0, -t], [t, t], [-t, -t], [t, -t], [-t, t]].map(([dx, dy]) => `${dx}px ${dy}px 0 ${c}`).join(",");
				}
				const textGradient = p.BackgroundTransparency >= 1 ? gradientOf(n) : undefined;
				if (textGradient) {
					span.style.background = background({ BackgroundColor3: { r: 1, g: 1, b: 1 }, BackgroundTransparency: 0 }, textGradient);
					span.style.webkitBackgroundClip = "text";
					span.style.backgroundClip = "text";
					span.style.color = "transparent";
					span.style.textShadow = "none";
				}
				if (p.RichText) span.innerHTML = text.replace(/<font color="(#[0-9A-Fa-f]{6})">/g, '<span style="color:$1">').replace(/<\/font>/g, "</span>");
				else span.textContent = text;
				box.appendChild(span);
				el.appendChild(box);
				const sizeCap = kid(n, "UITextSizeConstraint");
				texts.push({ span, cw, ch, size: p.TextScaled ? null : p.TextSize, max: sizeCap ? sizeCap.props.MaxTextSize : Infinity });
			}
		}

		const content = document.createElement("div");
		Object.assign(content.style, { position: "absolute", left: `${pl}px`, top: `${pt}px`, width: `${cw}px`, height: `${ch}px` });
		el.appendChild(content);

		const list = kid(n, "UIListLayout"), grid = kid(n, "UIGridLayout");
		let guiKids = kids(n).filter((c) => GUI.has(c.class) && c.props.Visible !== false);
		if (list || grid) guiKids = guiKids.slice().sort((a, b) => a.props.LayoutOrder - b.props.LayoutOrder);

		if (grid) {
			const g = grid.props;
			let cellW = g.CellSize.xs * cw + g.CellSize.xo, cellH = g.CellSize.ys * ch + g.CellSize.yo;
			const ar = kid(grid, "UIAspectRatioConstraint");
			if (ar) cellH = cellW / ar.props.AspectRatio;
			const gapX = g.CellPadding.xs * cw + g.CellPadding.xo, gapY = g.CellPadding.ys * ch + g.CellPadding.yo;
			const cols = Math.max(1, Math.floor((cw + gapX + 1e-6) / (cellW + gapX)));
			guiKids.forEach((c, i) => {
				render(c, content, cw, ch, { x: (i % cols) * (cellW + gapX), y: Math.floor(i / cols) * (cellH + gapY), w: cellW, h: cellH });
			});
		} else if (list) {
			const l = list.props, horizontal = l.FillDirection === "Horizontal";
			const gap = l.Padding.s * (horizontal ? cw : ch) + l.Padding.o;
			let cursor = 0;
			for (const c of guiKids) {
				const [kw, kh] = sizeOf(c, cw, ch);
				const cross = horizontal
					? { Top: 0, Center: (ch - kh) / 2, Bottom: ch - kh }[l.VerticalAlignment]
					: { Left: 0, Center: (cw - kw) / 2, Right: cw - kw }[l.HorizontalAlignment];
				render(c, content, cw, ch, horizontal ? { x: cursor, y: cross, w: kw, h: kh } : { x: cross, y: cursor, w: kw, h: kh });
				cursor += (horizontal ? kw : kh) + gap;
			}
		} else {
			for (const c of guiKids) render(c, content, cw, ch);
		}
	}

	const screen = document.getElementById("screen");
	render({ ...tree, props: { ...tree.props, Size: { xs: 1, xo: 0, ys: 1, yo: 0 }, Position: { xs: 0, xo: 0, ys: 0, yo: 0 }, AnchorPoint: { x: 0, y: 0 }, BackgroundTransparency: 1 } },
		screen, screen.clientWidth, screen.clientHeight);

	// TextScaled: largest size that fits the text box on one line.
	for (const t of texts) {
		let size = Math.min(t.size ?? t.ch, t.max);
		t.span.style.fontSize = `${size}px`;
		if (t.size == null) {
			while (size > 1 && t.span.getBoundingClientRect().width > t.cw + 0.5) {
				size -= 0.25;
				t.span.style.fontSize = `${size}px`;
			}
		}
	}
}

const html = `<!doctype html><html><head><meta charset="utf-8"><style>
${fontFaces}
html,body{margin:0;height:100%;overflow:hidden}
#screen{position:relative;width:100%;height:100%;overflow:hidden;
  background:
    radial-gradient(ellipse at 20% 15%, #3b4a3a 0%, transparent 45%),
    radial-gradient(ellipse at 75% 10%, #2e3c33 0%, transparent 40%),
    radial-gradient(ellipse at 60% 90%, #6d7c8f 0%, transparent 55%),
    linear-gradient(180deg, #1d2a24 0%, #33423a 38%, #707d8b 62%, #8793a1 100%);}
#screen.tiles{background:
    linear-gradient(180deg,#1b2129 0%,#2a323d 34%,rgba(0,0,0,0) 34%),
    repeating-conic-gradient(#eef2ff 0% 25%,#2b3a9c 0% 50%) 0 0/84px 84px;}
.npc{position:absolute;background:#15151c;border-radius:14px 14px 6px 6px}
.npc.head{border-radius:50%;background:#e8b98f}
.bench{position:absolute;background:#6b4a2b;border-radius:4px}
</style></head><body><div id="screen"></div></body></html>`;

// A few blocks behind the card so the see-through background is visible.
function addScene(scene) {
	const screen = document.getElementById("screen");
	if (scene !== "tiles") return;
	screen.classList.add("tiles");
	const w = screen.clientWidth, h = screen.clientHeight;
	const box = (cls, x, y, bw, bh) => {
		const d = document.createElement("div");
		d.className = cls;
		Object.assign(d.style, { left: `${x * w}px`, top: `${y * h}px`, width: `${bw * w}px`, height: `${bh * h}px` });
		screen.appendChild(d);
	};
	box("bench", 0.05, 0.36, 0.5, 0.05);
	box("bench", 0.34, 0.5, 0.55, 0.05);
	box("npc", 0.1, 0.5, 0.09, 0.28);
	box("npc head", 0.115, 0.43, 0.05, 0.09);
	box("npc", 0.62, 0.52, 0.08, 0.26);
	box("npc head", 0.64, 0.45, 0.045, 0.085);
}

(async () => {
	const htmlPath = path.join(ROOT, "build/preview.html");
	fs.writeFileSync(htmlPath, html);
	const browser = await chromium.launch();
	for (const shot of SHOTS.filter((s) => !process.argv[2] || s.file.includes(process.argv[2]))) {
		const page = await browser.newPage({ viewport: { width: shot.width, height: shot.height }, deviceScaleFactor: 2 });
		await page.goto(`file://${htmlPath}`);
		// Webfonts load lazily; load every weight before TextScaled measuring.
		await page.evaluate(() => Promise.all([400, 500, 600, 700, 800].map((w) => document.fonts.load(`${w} 16px Montserrat`))));
		if (!fs.existsSync(path.join(ROOT, shot.tree))) {
			console.log(`Skip ${shot.file} (${shot.tree} not built)`);
			await page.close();
			continue;
		}
		const tree = readTree(shot.tree);
		tree.previewDir = path.join(ROOT, "tools/preview");
		await page.evaluate(addScene, shot.scene);
		await page.evaluate(renderGui, tree);
		await page.screenshot({ path: path.join(ROOT, shot.file) });
		console.log(`Wrote ${shot.file}`);
		await page.close();
	}
	await browser.close();
})();
