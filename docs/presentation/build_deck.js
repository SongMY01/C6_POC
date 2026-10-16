// Learning Communication deck (10 slides, English). Run: node build_deck.js
// Output: ../presentation/26_C6_Learning Communication.pptx  (then converted to .key via Keynote)
const path = require("path");
const pptxgen = require("pptxgenjs");
const SKILL = "/Users/myone/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin/a3c41a07-c17f-44f0-b864-0f681e8947fe/58c2d3a6-e5ed-498b-b1c7-36bf143e8d5e/skills/pptx";
const { applyTheme } = require(path.join(SKILL, "scripts/apply_theme.js"));

const FONT = "Helvetica Neue";
const THEME = {
  name: "Band Practice Dark",
  headFontFace: FONT,
  bodyFontFace: FONT,
  colors: {
    dk1: "000000", lt1: "FFFFFF", dk2: "1A1A1A", lt2: "A0A0A0",
    accent1: "F5A524", accent2: "3DD6F5", accent3: "4A4A4A",
    accent4: "7BD88F", accent5: "C8A2E8", accent6: "E5484D",
    hlink: "3DD6F5", folHlink: "A0A0A0",
  },
};
const BG = "000000", FG = "FFFFFF", MUTED = "A0A0A0", CARD = "1A1A1A", AMBER = "F5A524", CYAN = "3DD6F5";
const W = 13.333, MX = 0.8;

const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE";
pres.title = "Learning Communication";
pres.theme = { headFontFace: FONT, bodyFontFace: FONT };

pres.defineSlideMaster({
  title: "DARK", background: { color: BG },
  objects: [{ placeholder: { options: { name: "title", type: "title", x: MX, y: 0.5, w: 11.7, h: 0.9, fontSize: 32, bold: true, color: FG, align: "left", valign: "top", margin: 0 }, text: "" } }],
});
pres.defineSlideMaster({
  title: "FLOW", background: { color: BG },
  objects: [{ placeholder: { options: { name: "title", type: "title", x: MX, y: 1.3, w: 6.4, h: 1.9, fontSize: 40, bold: true, color: FG, align: "left", valign: "top", margin: 0 }, text: "" } }],
});

const t = (s, text, o) => s.addText(text, Object.assign({ isTextBox: true, fontFace: FONT, color: FG, margin: 0, valign: "top" }, o));

// ---------- 1. Title ----------
{
  const s = pres.addSlide({ masterName: "DARK" });
  s.addImage({ path: "wave_hi.png", x: MX, y: 1.0, w: 11.7, h: 1.46, altText: "Waveform with one highlighted section" });
  t(s, "Starting Practice, Together", { x: MX, y: 3.3, w: 11.7, h: 1.0, fontSize: 54, bold: true });
  t(s, "Helping band members start practicing the feedback they receive", { x: MX, y: 4.45, w: 11.7, h: 0.6, fontSize: 24 });
  t(s, "2026 Challenge 6  ·  Learning Communication", { x: MX, y: 6.4, w: 8, h: 0.4, fontSize: 14, bold: true });
  s.addNotes("Intro (30s). We build for bands: after rehearsal, how do players actually start practicing the feedback they got?");
}

// ---------- 2. Team ----------
{
  const s = pres.addSlide({ masterName: "DARK" });
  s.addText("Our Team", { placeholder: "title" });
  const D = 1.5;
  const pts = [[4.9, 1.7], [7.0, 1.7], [3.85, 4.1], [5.95, 4.1], [8.05, 4.1]];
  pts.forEach(([x, y], i) => {
    s.addShape(pres.ShapeType.ellipse, { x, y, w: D, h: D, fill: { color: CARD }, line: { color: "4A4A4A", width: 1 }, objectName: `Member ${i + 1} photo` });
    t(s, "Nickname", { x: x - 0.4, y: y + D + 0.15, w: D + 0.8, h: 0.35, fontSize: 16, bold: true, align: "center" });
    t(s, "Role", { x: x - 0.4, y: y + D + 0.5, w: D + 0.8, h: 0.3, fontSize: 12, color: MUTED, align: "center" });
  });
  s.addNotes("Introduce each member by nickname and role (replace the placeholders and drop in photos).");
}

// ---------- 3. Story & Context (1/2) ----------
{
  const s = pres.addSlide({ masterName: "DARK" });
  s.addText("Story & Context", { placeholder: "title" });
  const rows = [
    ["Together", "Shows go well when the band rehearses together a lot."],
    ["In between", "Solo practice isn’t only your own part — it’s the places where you must lock in with the other sessions."],
    ["What worked", "Before a show, only the drums were recorded at rehearsal. Practicing while listening to just that worked well."],
  ];
  rows.forEach(([label, body], i) => {
    const y = 1.6 + i * 1.3;
    t(s, label, { x: MX, y, w: 2.7, h: 0.5, fontSize: 20, bold: true, color: AMBER });
    t(s, body, { x: 3.7, y, w: 8.8, h: 1.2, fontSize: 24 });
  });
  s.addImage({ path: "wave_plain.png", x: MX, y: 5.75, w: 11.7, h: 1.46, altText: "Waveform" });
  s.addNotes('Story 1/2 (1 min). Shows go well with lots of joint rehearsal. Between rehearsals, solo practice means locking in with other sessions. Example: a drums-only recording helped.');
}

// ---------- 3b. Story & Context (2/2) ----------
{
  const s = pres.addSlide({ masterName: "DARK" });
  s.addText("Story & Context", { placeholder: "title" });
  t(s, "Feedback and recordings are scattered across chat apps like KakaoTalk — and everyone remembers it differently.", { x: MX, y: 1.6, w: 11.4, h: 1.3, fontSize: 28, bold: true });
  const chips = ["Full-band recording", "Per-session recordings", "Section clips", "“Bass — rushing around 1:20”", "Who said what?", "Which one is the latest?"];
  const pos = [[0.8, 3.3, 3.2, -3], [4.7, 3.75, 3.5, 2], [9.0, 3.25, 2.8, -2], [1.4, 4.75, 4.6, 2], [6.7, 4.85, 2.9, -3], [9.6, 4.45, 2.9, 3]];
  chips.forEach((label, i) => {
    const [x, y, w, rot] = pos[i];
    s.addShape(pres.ShapeType.roundRect, { x, y, w, h: 0.65, rectRadius: 0.32, rotate: rot, fill: { color: CARD }, line: { color: "4A4A4A", width: 1 }, objectName: `Scattered ${i + 1}` });
    t(s, label, { x, y, w, h: 0.65, fontSize: 16, bold: true, align: "center", valign: "middle", rotate: rot });
  });
  t(s, "So practice never starts, and feedback begins to feel like homework.", { x: MX, y: 6.15, w: 11.7, h: 0.6, fontSize: 24, color: AMBER });
  s.addNotes('Story 2/2 (1 min). Today the feedback, full recordings, per-session files and section clips are scattered in chat; memories differ, so it is hard to begin.');
}

// ---------- 4. Target Use Case ----------
{
  const s = pres.addSlide({ masterName: "DARK" });
  s.addText("Target Use Case", { placeholder: "title" });
  const rows = [
    ["User", "Amateur band members who receive feedback from their bandmates"],
    ["Moment", "Right after a rehearsal — practicing alone, on their own instrument"],
    ["Pain Point", "Feedback is detached from the sound. It is hard to find the exact moment, and hard to know where to begin."],
  ];
  rows.forEach(([label, body], i) => {
    const y = 1.85 + i * 1.7;
    t(s, label, { x: MX, y, w: 2.6, h: 0.5, fontSize: 20, bold: true, color: AMBER });
    t(s, body, { x: 3.6, y, w: 8.9, h: 1.3, fontSize: 28 });
  });
  s.addNotes("Target (1 min). Who: band members. Pain: no link between the note and the sound, no obvious first step.");
}

// ---------- 5. Challenge Response ----------
{
  const s = pres.addSlide({ masterName: "DARK" });
  s.addText("Challenge Response", { placeholder: "title" });
  t(s, "GUIDING QUESTION", { x: MX, y: 1.6, w: 6, h: 0.3, fontSize: 12, bold: true, color: MUTED, charSpacing: 3 });
  t(s, "How might we help band members start practicing the feedback they receive?", { x: MX, y: 1.95, w: 11.2, h: 1.7, fontSize: 38, bold: true });
  t(s, "OUR RESPONSE", { x: MX, y: 3.95, w: 6, h: 0.3, fontSize: 12, bold: true, color: AMBER, charSpacing: 3 });
  t(s, "An iPad app that separates a rehearsal recording into instrument tracks, pins each piece of feedback to its exact moment, and turns it into a short, game-like practice.", { x: MX, y: 4.3, w: 11.2, h: 1.2, fontSize: 22 });
  ["Pinned to the sound", "Two takes at most", "Play, not homework"].forEach((label, i) => {
    const x = MX + i * 3.15;
    s.addShape(pres.ShapeType.roundRect, { x, y: 5.95, w: 2.9, h: 0.65, rectRadius: 0.32, fill: { color: CARD }, line: { color: "4A4A4A", width: 1 }, objectName: `Chip ${i + 1}` });
    t(s, label, { x, y: 5.95, w: 2.9, h: 0.65, fontSize: 16, bold: true, align: "center", valign: "middle" });
  });
  s.addNotes("Response (1 min). Three ideas: feedback lives on the sound; max two takes so it never feels endless; game-like but never competitive.");
}

// ---------- 6-7. Lo-Fi flows with screenshots ----------
function flowSlide(num, title, body, img, alt, note) {
  const s = pres.addSlide({ masterName: "FLOW" });
  t(s, "Lo-Fi Prototype (Flow)", { x: MX, y: 0.7, w: 6, h: 0.35, fontSize: 14, color: MUTED });
  s.addText(title, { placeholder: "title" });
  t(s, body, { x: MX, y: 3.7, w: 6.0, h: 2.6, fontSize: 22 });
  const fw = 4.925, fh = 6.5, fx = W - 0.6 - fw;
  s.addShape(pres.ShapeType.roundRect, { x: fx, y: 0.5, w: fw, h: fh, rectRadius: 0.18, fill: { color: CARD }, line: { color: "4A4A4A", width: 1 }, objectName: "Device frame" });
  s.addImage({ path: img, x: fx + 0.1, y: 0.6, w: 4.725, h: 6.3, altText: alt });
  s.addNotes(note);
  return s;
}
flowSlide(1, "1. Feedback lives on the sound",
  "The rehearsal is split into one track per instrument. Each note from a bandmate is pinned to the exact section on that player’s track — tap it to loop just that moment.",
  "../screenshots/B_1_메인.png", "iPad player: five instrument tracks with feedback markers on the timeline",
  "Flow 1 (1 min). Separated tracks (vocal, drums, bass, guitar, piano); markers show feedback and its status.");
flowSlide(2, "2. Two takes, then done",
  "Re-record only that section — at most two takes. Bandmates answer with a short comment or a one-tap cheer, and the last take is added to the song automatically.",
  "../screenshots/B_2_응원리액션.png", "Feedback sheet with cheer reactions and a two-take limit message",
  "Flow 2 (1 min). The two-take limit keeps it light; cheers need no words. (App UI is in Korean in this prototype.)");

// ---------- 8. Flow 3: tempo ladder (diagram) ----------
{
  const s = pres.addSlide({ masterName: "FLOW" });
  t(s, "Lo-Fi Prototype (Flow)", { x: MX, y: 0.7, w: 6, h: 0.35, fontSize: 14, color: MUTED });
  s.addText("3. A gentle way in", { placeholder: "title" });
  t(s, "Tap “Try it” and a four-beat count-in starts. The section loops slowly at first, then speeds up to full tempo — the pitch never changes. Not sure where to begin? Draw today’s section.", { x: MX, y: 3.7, w: 6.0, h: 2.8, fontSize: 22 });
  // count-in
  s.addShape(pres.ShapeType.ellipse, { x: 7.4, y: 4.95, w: 1.3, h: 1.3, fill: { color: CARD }, line: { color: AMBER, width: 2 }, objectName: "Count-in" });
  t(s, "1 2 3 4", { x: 7.4, y: 4.95, w: 1.3, h: 1.3, fontSize: 18, bold: true, align: "center", valign: "middle" });
  t(s, "count-in", { x: 7.2, y: 6.4, w: 1.7, h: 0.3, fontSize: 12, color: MUTED, align: "center" });
  // ladder
  const rungs = [["70%", "2 loops", 2.0, "4A4A4A"], ["85%", "2 loops", 2.6, "6E6E6E"], ["100%", "1 loop", 3.2, AMBER]];
  rungs.forEach(([pct, loops, h, col], i) => {
    const x = 9.2 + i * 1.3;
    s.addShape(pres.ShapeType.rect, { x, y: 6.25 - h, w: 1.1, h, fill: { color: col }, line: { color: col, width: 0 }, objectName: `Rung ${pct}` });
    t(s, pct, { x, y: 6.25 - h - 0.55, w: 1.1, h: 0.45, fontSize: 24, bold: true, align: "center", color: i === 2 ? AMBER : FG });
    t(s, loops, { x, y: 6.4, w: 1.1, h: 0.3, fontSize: 12, color: MUTED, align: "center" });
  });
  t(s, "Tempo ladder", { x: 9.2, y: 1.85, w: 3.9, h: 0.4, fontSize: 16, bold: true, color: MUTED });
  s.addNotes("Flow 3 (1 min). Count-in, then 70% x2, 85% x2, 100% x1 loops of the same section. Tempo changes without changing pitch.");
}

// ---------- 10. Learning Questions ----------
{
  const s = pres.addSlide({ masterName: "DARK" });
  s.addText("Learning Questions", { placeholder: "title" });
  const qs = [
    "Which game element helps people start practicing without turning it into competition?",
    "Could Apple’s Music Understanding framework (beats and bars) pin feedback to bars automatically — and how accurate is it on noisy band recordings?",
  ];
  qs.forEach((q, i) => {
    const y = 1.9 + i * 2.2;
    t(s, String(i + 1), { x: MX, y, w: 0.8, h: 0.9, fontSize: 48, bold: true, color: AMBER });
    t(s, q, { x: MX + 1.0, y: y + 0.05, w: 10.6, h: 1.8, fontSize: 28 });
  });
  s.addNotes("Close (30s). Two questions for the mentors; research and insight Q&A follows.");
}

(async () => {
  const out = path.join(__dirname, "26_C6_Learning Communication.pptx");
  await pres.writeFile({ fileName: out });
  await applyTheme(out, THEME);
  console.log("wrote", out);
})();
