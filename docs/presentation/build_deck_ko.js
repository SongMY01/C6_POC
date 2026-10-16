// Learning Communication deck (10 slides, English). Run: node build_deck.js
// Output: ../presentation/26_C6_Learning Communication.pptx  (then converted to .key via Keynote)
const path = require("path");
const pptxgen = require("pptxgenjs");
const SKILL = "/Users/myone/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin/a3c41a07-c17f-44f0-b864-0f681e8947fe/58c2d3a6-e5ed-498b-b1c7-36bf143e8d5e/skills/pptx";
const { applyTheme } = require(path.join(SKILL, "scripts/apply_theme.js"));

const FONT = "Apple SD Gothic Neo";
const THEME = {
  name: "Band Practice Dark KO",
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
pres.title = "Learning Communication (KO)";
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
  t(s, "함께 시작하는 연습", { x: MX, y: 3.3, w: 11.7, h: 1.0, fontSize: 54, bold: true });
  t(s, "받은 피드백을 밴드 멤버가 잘 시작할 수 있도록 돕기", { x: MX, y: 4.45, w: 11.7, h: 0.6, fontSize: 24 });
  t(s, "2026 Challenge 6  ·  Learning Communication", { x: MX, y: 6.4, w: 8, h: 0.4, fontSize: 14, bold: true });
  s.addNotes("도입 (30초). 합주가 끝난 뒤, 연주자들이 받은 피드백으로 어떻게 연습을 시작하는지에서 출발했습니다.");
}

// ---------- 2. Team ----------
{
  const s = pres.addSlide({ masterName: "DARK" });
  s.addText("팀 소개", { placeholder: "title" });
  const D = 1.5;
  const pts = [[4.9, 1.7], [7.0, 1.7], [3.85, 4.1], [5.95, 4.1], [8.05, 4.1]];
  pts.forEach(([x, y], i) => {
    s.addShape(pres.ShapeType.ellipse, { x, y, w: D, h: D, fill: { color: CARD }, line: { color: "4A4A4A", width: 1 }, objectName: `Member ${i + 1} photo` });
    t(s, "닉네임", { x: x - 0.4, y: y + D + 0.15, w: D + 0.8, h: 0.35, fontSize: 16, bold: true, align: "center" });
    t(s, "역할", { x: x - 0.4, y: y + D + 0.5, w: D + 0.8, h: 0.3, fontSize: 12, color: MUTED, align: "center" });
  });
  s.addNotes("팀원을 닉네임과 역할로 소개합니다 (자리 표시를 바꾸고 사진을 넣어 주세요).");
}

// ---------- 3. Story & Context (1/2) ----------
{
  const s = pres.addSlide({ masterName: "DARK" });
  s.addText("스토리 & 배경", { placeholder: "title" });
  const rows = [
    ["같이 할수록", "공연 준비는 합주를 많이 할수록 잘 됩니다."],
    ["합주 사이", "합주와 합주 사이의 개인 연습은 내 파트만이 아니라,\n다른 세션과 맞춰야 하는 부분을 연습하는 시간입니다."],
    ["잘 됐던 경험", "공연을 앞두고 합주 때 드럼만 따로 녹음해서,\n그것만 들으며 개인 연습했을 때 좋았습니다."],
  ];
  rows.forEach(([label, body], i) => {
    const y = 1.6 + i * 1.3;
    t(s, label, { x: MX, y, w: 2.7, h: 0.5, fontSize: 20, bold: true, color: AMBER });
    t(s, body, { x: 3.7, y, w: 8.8, h: 1.2, fontSize: 24 });
  });
  s.addImage({ path: "wave_plain.png", x: MX, y: 5.75, w: 11.7, h: 1.46, altText: "Waveform" });
  s.addNotes('스토리 1/2 (1분). 공연은 합주를 많이 할수록 잘 되고, 합주 사이의 개인 연습은 다른 세션과 맞추는 연습입니다. 드럼만 녹음해 연습했던 경험.');
}

// ---------- 3b. Story & Context (2/2) ----------
{
  const s = pres.addSlide({ masterName: "DARK" });
  s.addText("스토리 & 배경", { placeholder: "title" });
  t(s, "피드백과 녹음이 카톡 등에 흩어져 있고, 사람마다 기억하는 게 달라요.", { x: MX, y: 1.6, w: 11.4, h: 1.3, fontSize: 28, bold: true });
  const chips = ["합주 전체 녹음", "세션별 녹음 파일", "특정 구간 녹음", "“베이스, 1분 20초쯤 달려요”", "누가 뭐라고 했더라?", "어느 게 최신이지?"];
  const pos = [[0.8, 3.3, 3.2, -3], [4.7, 3.75, 3.5, 2], [9.0, 3.25, 2.8, -2], [1.4, 4.75, 4.6, 2], [6.7, 4.85, 2.9, -3], [9.6, 4.45, 2.9, 3]];
  chips.forEach((label, i) => {
    const [x, y, w, rot] = pos[i];
    s.addShape(pres.ShapeType.roundRect, { x, y, w, h: 0.65, rectRadius: 0.32, rotate: rot, fill: { color: CARD }, line: { color: "4A4A4A", width: 1 }, objectName: `Scattered ${i + 1}` });
    t(s, label, { x, y, w, h: 0.65, fontSize: 16, bold: true, align: "center", valign: "middle", rotate: rot });
  });
  t(s, "그래서 연습은 시작되지 않고, 피드백은 숙제처럼 느껴집니다.", { x: MX, y: 6.15, w: 11.7, h: 0.6, fontSize: 24, color: AMBER });
  s.addNotes('스토리 2/2 (1분). 지금은 피드백·합주 파일·세션 녹음·구간 녹음이 채팅에 흩어져 기억이 서로 달라 시작하기 어렵습니다.');
}

// ---------- 4. Target Use Case ----------
{
  const s = pres.addSlide({ masterName: "DARK" });
  s.addText("타깃 유스케이스", { placeholder: "title" });
  const rows = [
    ["사용자", "밴드 동료에게 피드백을 받은 아마추어 밴드 멤버"],
    ["상황", "합주 직후, 자기 악기로 혼자 연습하는 순간"],
    ["문제점", "피드백이 소리와 떨어져 있어 정확한 지점을 찾기 어렵고, 어디서부터 시작할지 막막합니다."],
  ];
  rows.forEach(([label, body], i) => {
    const y = 1.85 + i * 1.7;
    t(s, label, { x: MX, y, w: 2.6, h: 0.5, fontSize: 20, bold: true, color: AMBER });
    t(s, body, { x: 3.6, y, w: 8.9, h: 1.3, fontSize: 28 });
  });
  s.addNotes("타깃 (1분). 대상은 밴드 멤버. 문제는 메모와 소리가 연결되지 않고 첫걸음이 막막하다는 점입니다.");
}

// ---------- 5. Challenge Response ----------
{
  const s = pres.addSlide({ masterName: "DARK" });
  s.addText("챌린지 대응", { placeholder: "title" });
  t(s, "가이드 질문", { x: MX, y: 1.6, w: 6, h: 0.3, fontSize: 12, bold: true, color: MUTED, charSpacing: 1 });
  t(s, "어떻게 하면 받은 피드백을 잘 시작할 수 있을까?", { x: MX, y: 1.95, w: 11.2, h: 1.7, fontSize: 38, bold: true });
  t(s, "우리의 해결", { x: MX, y: 3.95, w: 6, h: 0.3, fontSize: 12, bold: true, color: AMBER, charSpacing: 1 });
  t(s, "합주 녹음을 악기별 트랙으로 분리하고, 피드백을 정확한 순간에 붙여서,\n짧고 게임 같은 연습으로 바꿔 주는 iPad 앱", { x: MX, y: 4.3, w: 11.2, h: 1.2, fontSize: 22 });
  ["소리 위에 붙은 피드백", "녹음은 최대 2번", "숙제가 아닌 놀이"].forEach((label, i) => {
    const x = MX + i * 3.15;
    s.addShape(pres.ShapeType.roundRect, { x, y: 5.95, w: 2.9, h: 0.65, rectRadius: 0.32, fill: { color: CARD }, line: { color: "4A4A4A", width: 1 }, objectName: `Chip ${i + 1}` });
    t(s, label, { x, y: 5.95, w: 2.9, h: 0.65, fontSize: 16, bold: true, align: "center", valign: "middle" });
  });
  s.addNotes("해결 (1분). 세 가지: 피드백이 소리 위에 있고, 녹음은 최대 2번이라 끝이 있으며, 게임처럼 하되 경쟁은 없습니다.");
}

// ---------- 6-7. Lo-Fi flows with screenshots ----------
function flowSlide(num, title, body, img, alt, note) {
  const s = pres.addSlide({ masterName: "FLOW" });
  t(s, "Lo-Fi 프로토타입 (플로우)", { x: MX, y: 0.7, w: 6, h: 0.35, fontSize: 14, color: MUTED });
  s.addText(title, { placeholder: "title" });
  t(s, body, { x: MX, y: 3.7, w: 6.0, h: 2.6, fontSize: 22 });
  const fw = 4.925, fh = 6.5, fx = W - 0.6 - fw;
  s.addShape(pres.ShapeType.roundRect, { x: fx, y: 0.5, w: fw, h: fh, rectRadius: 0.18, fill: { color: CARD }, line: { color: "4A4A4A", width: 1 }, objectName: "Device frame" });
  s.addImage({ path: img, x: fx + 0.1, y: 0.6, w: 4.725, h: 6.3, altText: alt });
  s.addNotes(note);
  return s;
}
flowSlide(1, "1. 피드백이 소리 위에 있어요",
  "합주가 악기별 트랙으로 나뉩니다.\n동료의 메모는 그 연주자의 트랙 위\n정확한 구간에 붙어 있고,\n탭하면 그 순간만 반복해서 들을 수 있어요.",
  "../screenshots/B_1_메인.png", "iPad 플레이어: 악기 5개 트랙과 타임라인 위 피드백 표시",
  "플로우 1 (1분). 분리된 트랙(보컬·드럼·베이스·기타·피아노)과 피드백 상태를 보여주는 표시.");
flowSlide(2, "2. 두 번이면 끝",
  "그 구간만 다시 녹음하고, 기회는 최대 2번.\n동료는 짧은 코멘트나\n한 번의 응원 탭으로 답하고,\n마지막 녹음은 곡에 자동으로 반영돼요.",
  "../screenshots/B_2_응원리액션.png", "응원 리액션과 2번 녹음 제한 안내가 있는 피드백 창",
  "플로우 2 (1분). 2번 제한으로 부담을 줄이고, 응원은 말 없이 탭 한 번으로 전할 수 있습니다.");

// ---------- 8. Flow 3: tempo ladder (diagram) ----------
{
  const s = pres.addSlide({ masterName: "FLOW" });
  t(s, "Lo-Fi 프로토타입 (플로우)", { x: MX, y: 0.7, w: 6, h: 0.35, fontSize: 14, color: MUTED });
  s.addText("3. 부드러운 시작", { placeholder: "title" });
  t(s, "“바로 해보기”를 누르면\n네 박자 카운트인이 시작돼요.\n구간을 처음엔 느리게 반복하다\n원래 속도까지 올라가요.\n음높이는 그대로예요.\n어디서 시작할지 모르겠다면\n오늘의 구간을 뽑아 보세요.", { x: MX, y: 3.7, w: 6.2, h: 3.2, fontSize: 22 });
  // count-in
  s.addShape(pres.ShapeType.ellipse, { x: 7.4, y: 4.95, w: 1.3, h: 1.3, fill: { color: CARD }, line: { color: AMBER, width: 2 }, objectName: "Count-in" });
  t(s, "1 2 3 4", { x: 7.4, y: 4.95, w: 1.3, h: 1.3, fontSize: 18, bold: true, align: "center", valign: "middle" });
  t(s, "카운트인", { x: 7.2, y: 6.4, w: 1.7, h: 0.3, fontSize: 12, color: MUTED, align: "center" });
  // ladder
  const rungs = [["70%", "2바퀴", 2.0, "4A4A4A"], ["85%", "2바퀴", 2.6, "6E6E6E"], ["100%", "1바퀴", 3.2, AMBER]];
  rungs.forEach(([pct, loops, h, col], i) => {
    const x = 9.2 + i * 1.3;
    s.addShape(pres.ShapeType.rect, { x, y: 6.25 - h, w: 1.1, h, fill: { color: col }, line: { color: col, width: 0 }, objectName: `Rung ${pct}` });
    t(s, pct, { x, y: 6.25 - h - 0.55, w: 1.1, h: 0.45, fontSize: 24, bold: true, align: "center", color: i === 2 ? AMBER : FG });
    t(s, loops, { x, y: 6.4, w: 1.1, h: 0.3, fontSize: 12, color: MUTED, align: "center" });
  });
  t(s, "템포 사다리", { x: 9.2, y: 1.85, w: 3.9, h: 0.4, fontSize: 16, bold: true, color: MUTED });
  s.addNotes("플로우 3 (1분). 카운트인 뒤 같은 구간을 70% 2바퀴, 85% 2바퀴, 100% 1바퀴. 속도만 바뀌고 음높이는 그대로입니다.");
}

// ---------- 10. Learning Questions ----------
{
  const s = pres.addSlide({ masterName: "DARK" });
  s.addText("러닝 퀘스천", { placeholder: "title" });
  const qs = [
    "경쟁처럼 느껴지지 않으면서\n연습을 시작하게 만드는 게임 요소는?",
    "Apple의 Music Understanding(박·마디 분석)으로\n피드백을 마디에 자동으로 붙일 수 있을까?\n소음 많은 합주 녹음에서도 정확할까?",
  ];
  qs.forEach((q, i) => {
    const y = 1.9 + i * 2.2;
    t(s, String(i + 1), { x: MX, y, w: 0.8, h: 0.9, fontSize: 48, bold: true, color: AMBER });
    t(s, q, { x: MX + 1.0, y: y + 0.05, w: 10.6, h: 1.8, fontSize: 28 });
  });
  s.addNotes("마무리 (30초). 멘토에게 묻고 싶은 질문 두 가지, 이어서 리서치·인사이트 Q&A.");
}

(async () => {
  const out = path.join(__dirname, "26_C6_Learning Communication_KO.pptx");
  await pres.writeFile({ fileName: out });
  await applyTheme(out, THEME);
  console.log("wrote", out);
})();
