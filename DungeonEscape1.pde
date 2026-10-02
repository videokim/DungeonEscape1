// ================================================================
//  어둠의 미궁 — DRPG 풍 1인칭 미로 탈출 게임
//  Processing 4.x  (P2D 렌더러)
//
//  조작
//    W / ↑   전진          S / ↓   후진
//    A / ←   왼쪽으로 회전   D / →   오른쪽으로 회전
//    Q / E   옆걸음(좌/우)   M       지도 켜기/끄기
//    R       새 미궁        ENTER   (탈출 후) 다음 층으로
//
//  목표: 어둠 속에서 푸른 빛이 새어 나오는 출구를 찾아 탈출하기
// ================================================================

import java.util.*;

final int[] DX = { 1, 0, -1, 0 };          // 동, 남, 서, 북
final int[] DY = { 0, 1, 0, -1 };
final String[] DIR_NAME = { "동", "남", "서", "북" };

// ---- 미궁 / 진행 상태 ----
int level = 1;
int mw, mh;
boolean[][] wall, seen;
int gx, gy, gd;              // 플레이어 격자 위치와 방향
int exitX, exitY;
int steps, startMillis, clearMillis;
boolean won = false;
float winFade = 0;
boolean showMap = true;
int pending = -1;            // 이동 중 눌린 키 1개 예약

// ---- 시점 애니메이션 ----
float fromX, fromZ, fromA, toX, toZ, toA;
float animT = 1;
final float MOVE_TIME = 0.17;
boolean lastWasMove = false;
float pX, pZ;                // 보간된 플레이어 위치
float camX, camZ, camA, eyeY = 0.5;
float sinA, cosA;
float bumpT = 0, shakeX = 0, shakeY = 0;

// ---- 투영 ----
float F;
final float NEAR = 0.05;
final float VIEW = 8.5;

// ---- 조명 ----
ArrayList<float[]> torches = new ArrayList<float[]>();  // {x, y, z, seed, nx, nz}
final int MAXL = 48;
float[] lx = new float[MAXL], ly = new float[MAXL], lz = new float[MAXL];
float[] li = new float[MAXL], lk = new float[MAXL];
float[] lr = new float[MAXL], lg = new float[MAXL], lb = new float[MAXL];
float[] lnx = new float[MAXL], lnz = new float[MAXL];
int nL;
float LR, LG, LB;
float flick = 1;
float gutter = 0;            // 횃불이 꺼질 듯 흔들리는 정도

// ---- 공포 연출 ----
float[] eyes = null;         // 어둠 속의 눈 {x, z, 남은시간, 투명도, 시드}
float eyeTimer = 8;
float heart = 0, heartPhase = 0;
String whisper = "";
float whisperT = 0, whisperTimer = 18;
final String[] WHISPERS = {
  "…발소리가 하나 더 들린다.",
  "뒤를 돌아보지 마라.",
  "횃불이 꺼져 간다.",
  "여기서 나간 자는 없었다.",
  "벽 너머에서 무언가 긁는 소리가 난다.",
  "숨소리가… 네 것이 아니다."
};

// ---- 연출 ----
PGraphics vignette, vignetteRed;
PFont font, fontMid, fontBig;
float[][] dust = new float[45][4];
int lastMillis;
float hintAlpha = 255;

// ================================================================
void setup() {
  size(960, 640, P2D);
  smooth(4);
  F = (width * 0.5) / tan(radians(40));   // 수평 시야각 80도
  font    = pickFont(17);
  fontMid = pickFont(26);
  fontBig = pickFont(52);
  makeVignette();
  for (float[] d : dust) resetDust(d, true);
  newGame();
  lastMillis = millis();
}

void draw() {
  int now = millis();
  float dt = min((now - lastMillis) / 1000.0, 0.05);
  lastMillis = now;

  update(dt);

  background(0);
  noStroke();
  renderWorld();
  drawDust(dt);
  image(vignette, 0, 0);
  drawHeartbeat();
  drawGrain();
  if (bumpT > 0) { noStroke(); fill(90, 0, 0, bumpT * 70); rect(0, 0, width, height); }
  drawWhisper();
  drawHUD();
  if (showMap) drawMinimap();
  if (won) drawWin(dt);
}

// ================================================================
//  게임 생성
// ================================================================
void newGame() {
  mw = min(13 + (level - 1) * 4, 41);
  if (mw % 2 == 0) mw++;
  mh = mw;
  generateMaze();
  seen = new boolean[mw][mh];

  gx = 1; gy = 1; gd = 0;
  for (int d = 0; d < 4; d++) if (!isWall(gx + DX[d], gy + DY[d])) { gd = d; break; }

  findExit();
  placeTorches();

  fromX = toX = gx + 0.5;  fromZ = toZ = gy + 0.5;
  fromA = toA = gd * HALF_PI;
  animT = 1; pending = -1;
  steps = 0; won = false; winFade = 0;
  startMillis = millis(); hintAlpha = 255;
  eyes = null; eyeTimer = random(7, 12);
  heart = 0; whisperT = 0; whisperTimer = random(15, 25);
  updateSeen();
}

void generateMaze() {
  wall = new boolean[mw][mh];
  for (int i = 0; i < mw; i++) for (int j = 0; j < mh; j++) wall[i][j] = true;

  // 깊이 우선 탐색(백트래킹)으로 미로 파기
  ArrayList<int[]> st = new ArrayList<int[]>();
  st.add(new int[]{1, 1});
  wall[1][1] = false;
  while (!st.isEmpty()) {
    int[] c = st.get(st.size() - 1);
    IntList opts = new IntList();
    for (int d = 0; d < 4; d++) {
      int nx = c[0] + DX[d] * 2, ny = c[1] + DY[d] * 2;
      if (nx > 0 && ny > 0 && nx < mw - 1 && ny < mh - 1 && wall[nx][ny]) opts.append(d);
    }
    if (opts.size() == 0) { st.remove(st.size() - 1); continue; }
    int d = opts.get((int) random(opts.size()));
    wall[c[0] + DX[d]][c[1] + DY[d]] = false;
    wall[c[0] + DX[d] * 2][c[1] + DY[d] * 2] = false;
    st.add(new int[]{c[0] + DX[d] * 2, c[1] + DY[d] * 2});
  }

  // 벽 몇 개를 허물어 순환 통로 만들기 (길 잃기 좋게)
  int holes = mw * mh / 45;
  for (int k = 0; k < holes; k++) {
    int x = 1 + (int) random(mw - 2), y = 1 + (int) random(mh - 2);
    boolean between = (x % 2 == 1 && y % 2 == 0) || (x % 2 == 0 && y % 2 == 1);
    if (wall[x][y] && between) wall[x][y] = false;
  }
}

void findExit() {
  // 시작점에서 가장 먼 칸을 출구로
  int[][] dist = new int[mw][mh];
  for (int[] row : dist) Arrays.fill(row, -1);
  ArrayList<int[]> q = new ArrayList<int[]>();
  q.add(new int[]{gx, gy});
  dist[gx][gy] = 0;
  exitX = gx; exitY = gy;
  int head = 0, best = 0;
  while (head < q.size()) {
    int[] c = q.get(head++);
    int cd = dist[c[0]][c[1]];
    if (cd > best) { best = cd; exitX = c[0]; exitY = c[1]; }
    for (int d = 0; d < 4; d++) {
      int nx = c[0] + DX[d], ny = c[1] + DY[d];
      if (!isWall(nx, ny) && dist[nx][ny] < 0) {
        dist[nx][ny] = cd + 1;
        q.add(new int[]{nx, ny});
      }
    }
  }
}

void placeTorches() {
  torches.clear();
  for (int i = 1; i < mw - 1; i++) for (int j = 1; j < mh - 1; j++) {
    if (wall[i][j] || random(1) > 0.045) continue;
    int d0 = (int) random(4);
    for (int t = 0; t < 4; t++) {
      int d = (d0 + t) % 4;
      if (isWall(i + DX[d], j + DY[d])) {
        torches.add(new float[]{ i + 0.5 + DX[d] * 0.45, 0.62, j + 0.5 + DY[d] * 0.45,
                                 random(1000), -DX[d], -DY[d],
                                 random(1) < 0.4 ? 1 : 0 });   // 마지막 값: 꺼진 횃불
        break;
      }
    }
  }
}

boolean isWall(int x, int y) {
  if (x < 0 || y < 0 || x >= mw || y >= mh) return true;
  return wall[x][y];
}

void markSeen(int x, int y) {
  if (x >= 0 && y >= 0 && x < mw && y < mh) seen[x][y] = true;
}

void updateSeen() {
  for (int a = -1; a <= 1; a++) for (int b = -1; b <= 1; b++) markSeen(gx + a, gy + b);
  for (int d = 0; d < 4; d++) {
    int x = gx, y = gy;
    for (int s = 0; s < 6; s++) {
      x += DX[d]; y += DY[d];
      markSeen(x, y);
      markSeen(x - DY[d], y + DX[d]);
      markSeen(x + DY[d], y - DX[d]);
      if (isWall(x, y)) break;
    }
  }
}

// ================================================================
//  입력 / 이동
// ================================================================
boolean isKey(char c, char ko) {
  return Character.toLowerCase(key) == c || key == ko || keyCode == Character.toUpperCase(c);
}

void keyPressed() {
  if (isKey('r', 'ㄱ')) { newGame(); return; }
  if (won) {
    if (key == ENTER || key == RETURN || key == ' ') { level++; newGame(); }
    return;
  }
  if (isKey('m', 'ㅡ')) { showMap = !showMap; return; }

  int a = -1;
  if (key == CODED) {
    if (keyCode == UP) a = 0;
    else if (keyCode == DOWN) a = 1;
    else if (keyCode == LEFT) a = 2;
    else if (keyCode == RIGHT) a = 3;
  } else if (isKey('w', 'ㅈ')) a = 0;
  else if (isKey('s', 'ㄴ')) a = 1;
  else if (isKey('a', 'ㅁ')) a = 2;
  else if (isKey('d', 'ㅇ')) a = 3;
  else if (isKey('q', 'ㅂ')) a = 4;
  else if (isKey('e', 'ㄷ')) a = 5;
  if (a < 0) return;

  if (animT < 1) pending = a;
  else doAction(a);
}

void doAction(int a) {
  switch (a) {
    case 0: tryMove(gd); break;
    case 1: tryMove((gd + 2) % 4); break;
    case 2: turn(-1); break;
    case 3: turn(1); break;
    case 4: tryMove((gd + 3) % 4); break;
    case 5: tryMove((gd + 1) % 4); break;
  }
}

void tryMove(int d) {
  int nx = gx + DX[d], ny = gy + DY[d];
  if (isWall(nx, ny)) { bumpT = 1; return; }   // 벽에 부딪힘
  fromX = toX; fromZ = toZ; fromA = toA; animT = 0;
  gx = nx; gy = ny;
  toX = gx + 0.5; toZ = gy + 0.5;
  lastWasMove = true;
  steps++;
  updateSeen();
}

void turn(int s) {
  fromX = toX; fromZ = toZ; fromA = toA; animT = 0;
  gd = (gd + s + 4) % 4;
  toA = fromA + s * HALF_PI;
  lastWasMove = false;
}

void update(float dt) {
  if (animT < 1) {
    animT = min(1, animT + dt / MOVE_TIME);
    if (animT >= 1) arrive();
  }
  float e = animT * animT * (3 - 2 * animT);
  pX = lerp(fromX, toX, e);
  pZ = lerp(fromZ, toZ, e);
  camA = lerp(fromA, toA, e);
  // 카메라를 칸 중심보다 살짝 뒤에 두어 양옆 벽이 보이게
  camX = pX - cos(camA) * 0.28;
  camZ = pZ - sin(camA) * 0.28;
  eyeY = 0.5 - (lastWasMove ? sin(animT * PI) * 0.022 : 0);   // 발걸음 흔들림

  bumpT = max(0, bumpT - dt * 3.5);
  shakeX = bumpT > 0 ? random(-1, 1) * bumpT * 7 : 0;
  shakeY = bumpT > 0 ? random(-1, 1) * bumpT * 4 : 0;

  // 가끔 횃불이 꺼질 듯 심하게 흔들림
  if (gutter <= 0 && random(1) < dt * 0.12) gutter = 1;
  gutter = max(0, gutter - dt * 0.9);
  float sputter = 0.4 + 0.6 * noise(millis() * 0.03);
  flick = (0.82 + 0.18 * noise(millis() * 0.004) + random(-0.02, 0.02))
          * lerp(1, sputter, min(1, gutter * 1.5));
  updateHorror(dt);
  if (millis() - startMillis > 7000) hintAlpha = max(0, hintAlpha - dt * 80);
}

void arrive() {
  if (gx == exitX && gy == exitY && !won) {
    won = true;
    clearMillis = millis();
    pending = -1;
    return;
  }
  if (pending >= 0) { int p = pending; pending = -1; doAction(p); }
}

// ================================================================
//  3D 렌더링 (화가 알고리즘 + 정점 조명)
// ================================================================
void renderWorld() {
  sinA = sin(camA); cosA = cos(camA);
  buildLights();

  int r = ceil(VIEW);
  int cx0 = floor(camX), cz0 = floor(camZ);
  float tanH = tan(radians(40));
  ArrayList<float[]> draws = new ArrayList<float[]>();

  for (int i = cx0 - r; i <= cx0 + r; i++) {
    for (int j = cz0 - r; j <= cz0 + r; j++) {
      if (i < 0 || j < 0 || i >= mw || j >= mh) continue;
      float dx = i + 0.5 - camX, dz = j + 0.5 - camZ;
      float f = dx * cosA + dz * sinA;
      float rr = -dx * sinA + dz * cosA;
      if (f < -0.8) continue;
      if (abs(rr) > max(f, 0) * tanH + 1.2) continue;     // 시야 밖
      float d = sqrt(dx * dx + dz * dz);
      if (d > VIEW) continue;
      if (wall[i][j]) draws.add(new float[]{ d, 0, i, j });
      else {
        drawFloorCell(i, j);                               // 바닥·천장은 먼저
        if (i == exitX && j == exitY) draws.add(new float[]{ d - 0.01, 1, i, j });
      }
    }
  }
  for (int k = 0; k < torches.size(); k++) {
    float[] t = torches.get(k);
    float dx = t[0] - camX, dz = t[2] - camZ;
    float d = sqrt(dx * dx + dz * dz);
    if (d < VIEW) draws.add(new float[]{ d, 2, k, 0 });
  }
  if (eyes != null) {
    float dx = eyes[0] - camX, dz = eyes[1] - camZ;
    draws.add(new float[]{ sqrt(dx * dx + dz * dz), 3, 0, 0 });
  }

  // 먼 것부터 그리기
  Collections.sort(draws, new Comparator<float[]>() {
    public int compare(float[] a, float[] b) { return Float.compare(b[0], a[0]); }
  });

  for (float[] dr : draws) {
    int type = (int) dr[1];
    if (type == 0) drawWallBlock((int) dr[2], (int) dr[3]);
    else if (type == 1) drawExit();
    else if (type == 2) drawTorch(torches.get((int) dr[2]));
    else drawEyes();
  }
  blendMode(BLEND);
  noStroke();
}

void drawWallBlock(int i, int j) {
  int s = (i * 131 + j * 977) * 4;
  if (camZ < j     && !isWall(i, j - 1)) wallFace(i + 1, j,     i,     j,     s,     0.92);
  if (camZ > j + 1 && !isWall(i, j + 1)) wallFace(i,     j + 1, i + 1, j + 1, s + 1, 0.92);
  if (camX < i     && !isWall(i - 1, j)) wallFace(i,     j,     i,     j + 1, s + 2, 0.78);
  if (camX > i + 1 && !isWall(i + 1, j)) wallFace(i + 1, j + 1, i + 1, j,     s + 3, 0.78);
}

// 돌벽 한 면을 벽돌 단위로 쪼개 그리기
void wallFace(float x0, float z0, float x1, float z1, int seed, float shade) {
  int rows = 5;
  for (int r = 0; r < rows; r++) {
    float y0 = r / (float) rows, y1 = (r + 1) / (float) rows;
    float off = (r % 2 == 0) ? 0 : 0.25;
    for (float u = -off; u < 0.999; u += 0.5) {
      float u0 = max(u, 0), u1 = min(u + 0.5, 1);
      if (u1 - u0 < 0.01) continue;
      float h = hash(seed, r, round(u * 4) + 2);
      float k = shade * (0.65 + 0.4 * h);
      float br = 78 * k, bg = 80 * k, bb = 76 * k;                            // 차갑고 축축한 돌
      if (r <= 1 && h > 0.6) { bg += 12 * k; br -= 10 * k; bb -= 4 * k; }    // 이끼와 습기
      if (h > 0.9) { br *= 0.5; bg *= 0.5; bb *= 0.5; }                       // 그을린 돌
      if (hash(seed, 7, 3) > 0.86 && r <= 2 && hash(seed, r, round(u * 4) + 11) > 0.35) {
        br = 72 * k; bg = 14 * k; bb = 12 * k;                                // 핏자국
      }
      quadWorld(lerp(x0, x1, u0), y0, lerp(z0, z1, u0),
                lerp(x0, x1, u1), y0, lerp(z0, z1, u1),
                lerp(x0, x1, u1), y1, lerp(z0, z1, u1),
                lerp(x0, x1, u0), y1, lerp(z0, z1, u0),
                br, bg, bb, true);
    }
  }
}

void drawFloorCell(int i, int j) {
  for (int a = 0; a < 2; a++) for (int b = 0; b < 2; b++) {
    float x0 = i + a * 0.5, x1 = x0 + 0.5, z0 = j + b * 0.5, z1 = z0 + 0.5;
    float h = hash(i * 7 + a, j * 13 + b, 5);
    float k = 0.7 + 0.38 * h;
    if (h > 0.965) quadWorld(x0, 0, z0, x1, 0, z0, x1, 0, z1, x0, 0, z1, 62 * k, 12 * k, 10 * k, true);  // 피 웅덩이
    else quadWorld(x0, 0, z0, x1, 0, z0, x1, 0, z1, x0, 0, z1, 56 * k, 54 * k, 50 * k, true);
    float k2 = 0.8 + 0.3 * hash(i * 7 + a, j * 13 + b, 9);
    quadWorld(x0, 1, z0, x1, 1, z0, x1, 1, z1, x0, 1, z1, 28 * k2, 27 * k2, 26 * k2, true);
  }
}

// 월드 좌표 사각형 → 카메라 공간 → 근평면 클리핑 → 투영 + 정점 조명
void quadWorld(float ax, float ay, float az, float bx, float by, float bz,
               float cx, float cy, float cz, float dx, float dy, float dz,
               float br, float bg, float bb, boolean mortar) {
  ArrayList<float[]> poly = new ArrayList<float[]>(6);
  poly.add(vtx(ax, ay, az)); poly.add(vtx(bx, by, bz));
  poly.add(vtx(cx, cy, cz)); poly.add(vtx(dx, dy, dz));
  boolean any = false;
  for (float[] v : poly) if (v[2] > NEAR) { any = true; break; }
  if (!any) return;
  poly = clipNear(poly);
  if (poly.size() < 3) return;

  if (mortar) strokeWeight(1.2); else noStroke();
  beginShape();
  for (float[] v : poly) {
    lightAt(v[3], v[4], v[5]);
    float fr = min(255, br * LR * 1.5), fg = min(255, bg * LG * 1.5), fb = min(255, bb * LB * 1.5);
    fill(fr, fg, fb);
    if (mortar) stroke(fr * 0.3, fg * 0.3, fb * 0.3);
    vertex(sxOf(v), syOf(v));
  }
  endShape(CLOSE);
}

// {카메라 오른쪽, 높이, 카메라 앞, 월드x, 월드y, 월드z}
float[] vtx(float x, float y, float z) {
  float dx = x - camX, dz = z - camZ;
  return new float[]{ -dx * sinA + dz * cosA, y, dx * cosA + dz * sinA, x, y, z };
}

float sxOf(float[] v) { return width * 0.5 + v[0] / v[2] * F + shakeX; }
float syOf(float[] v) { return height * 0.5 - (v[1] - eyeY) / v[2] * F + shakeY; }

ArrayList<float[]> clipNear(ArrayList<float[]> in) {
  ArrayList<float[]> out = new ArrayList<float[]>(8);
  int n = in.size();
  for (int i = 0; i < n; i++) {
    float[] a = in.get(i), b = in.get((i + 1) % n);
    boolean ia = a[2] > NEAR, ib = b[2] > NEAR;
    if (ia) out.add(a);
    if (ia != ib) {
      float t = (NEAR - a[2]) / (b[2] - a[2]);
      float[] c = new float[a.length];
      for (int k = 0; k < a.length; k++) c[k] = a[k] + (b[k] - a[k]) * t;
      out.add(c);
    }
  }
  return out;
}

float hash(int a, int b, int c) {
  int h = a * 73856093 ^ b * 19349663 ^ c * 83492791;
  h = (h ^ (h >>> 13)) * 1274126177;
  h ^= (h >>> 16);
  return (h & 0xFFFF) / 65535.0;
}

// ---- 조명 ----
void addLight(float x, float y, float z, float inten, float fall,
              float r, float g, float b, float nx, float nz) {
  if (nL >= MAXL) return;
  lx[nL] = x; ly[nL] = y; lz[nL] = z; li[nL] = inten; lk[nL] = fall;
  lr[nL] = r; lg[nL] = g; lb[nL] = b; lnx[nL] = nx; lnz[nL] = nz;
  nL++;
}

void buildLights() {
  nL = 0;
  // 플레이어가 든 횃불
  addLight(camX, 0.55, camZ, 0.95 * flick, 0.6, 1.0, 0.68, 0.42, 0, 0);
  // 출구의 푸른 빛
  float pulse = 0.8 + 0.2 * sin(millis() * 0.003);
  addLight(exitX + 0.5, 0.5, exitY + 0.5, 1.0 * pulse, 1.8, 0.35, 0.7, 1.0, 0, 0);
  // 벽걸이 횃불 (꺼진 것은 제외)
  for (float[] t : torches) {
    if (t[6] > 0.5) continue;
    float dx = t[0] - camX, dz = t[2] - camZ;
    if (dx * dx + dz * dz < (VIEW + 2) * (VIEW + 2)) {
      float fl = 0.7 + 0.4 * noise(t[3], millis() * 0.005);
      addLight(t[0], t[1], t[2], 0.9 * fl, 2.0, 1.0, 0.5, 0.22, t[4], t[5]);
    }
  }
}

void lightAt(float x, float y, float z) {
  LR = LG = LB = 0.008;  // 거의 없는 환경광
  for (int i = 0; i < nL; i++) {
    float dx = x - lx[i], dy = y - ly[i], dz = z - lz[i];
    if (dx * lnx[i] + dz * lnz[i] < -0.1) continue;   // 벽 뒤로 새지 않게
    float a = li[i] / (1 + lk[i] * (dx * dx + dy * dy + dz * dz));
    LR += a * lr[i]; LG += a * lg[i]; LB += a * lb[i];
  }
}

// ---- 스프라이트 ----
void drawTorch(float[] t) {
  float facing = (camX - t[0]) * t[4] + (camZ - t[2]) * t[5];
  if (facing <= 0) return;
  float[] c = vtx(t[0], t[1], t[2]);
  if (c[2] < 0.15) return;
  float sx = sxOf(c), sy = syOf(c), s = F / c[2];
  float fl = 0.75 + 0.35 * noise(t[3], millis() * 0.005);
  float fade = constrain(1.3 - c[2] / VIEW, 0.15, 1);

  // 쇠 받침대
  float[] b = vtx(t[0] - t[4] * 0.05, t[1] - 0.16, t[2] - t[5] * 0.05);
  if (b[2] > NEAR) {
    stroke(28 * fade + 10, 22 * fade + 8, 18 * fade + 6);
    strokeWeight(max(1.5, s * 0.022));
    line(sx, sy + s * 0.01, sxOf(b), syOf(b));
  }
  noStroke();
  blendMode(ADD);
  if (t[6] > 0.5) {   // 꺼진 횃불: 희미한 불씨만
    fill(160, 30, 10, 90 * fade * fl);
    ellipse(sx, sy, s * 0.02, s * 0.015);
    blendMode(BLEND);
    return;
  }
  for (int k = 5; k >= 1; k--) {
    fill(255, 110, 30, 14 * fade * fl);
    float rr = s * 0.09 * k;
    ellipse(sx, sy - s * 0.03, rr, rr * 1.15);
  }
  fill(255, 140, 45, 190 * fade);
  ellipse(sx, sy - s * 0.035, s * 0.05 * fl, s * 0.12 * fl);
  fill(255, 235, 170, 220 * fade);
  ellipse(sx, sy - s * 0.025, s * 0.022, s * 0.05 * fl);
  blendMode(BLEND);
}

void drawExit() {
  float ex = exitX + 0.5, ez = exitY + 0.5;
  float[] c = vtx(ex, 0.5, ez);
  if (c[2] < 0.2) return;
  float sx = sxOf(c), sy = syOf(c), s = F / c[2];
  float t = millis() * 0.001;
  blendMode(ADD);
  noStroke();

  // 바닥의 마법진
  noFill();
  stroke(110, 190, 255, 170);
  strokeWeight(max(1, s * 0.006));
  drawFloorRing(ex, ez, 0.38, 0, 32, 1);
  stroke(110, 190, 255, 120);
  drawFloorRing(ex, ez, 0.30, t * 0.6, 6, 2);   // 회전하는 육망성
  noStroke();

  // 빛기둥
  float top = height * 0.5 - (1 - eyeY) / c[2] * F + shakeY;
  fill(50, 110, 210, 18);
  rect(sx - s * 0.16, top, s * 0.32, s);
  fill(90, 160, 255, 28);
  rect(sx - s * 0.07, top, s * 0.14, s);

  // 후광
  for (int k = 6; k >= 1; k--) {
    fill(30, 70, 140, 13);
    ellipse(sx, sy, s * 0.18 * k, s * 0.24 * k);
  }

  // 떠오르는 빛 입자
  for (int k = 0; k < 14; k++) {
    float ph = (t * 0.35 + k / 14.0) % 1.0;
    float ang = k * 2.4 + t;
    float[] p = vtx(ex + cos(ang) * 0.25, ph, ez + sin(ang) * 0.25);
    if (p[2] <= NEAR) continue;
    float ps = F / p[2] * 0.025;
    fill(170, 220, 255, 220 * (1 - ph));
    ellipse(sxOf(p), syOf(p), ps, ps);
  }
  blendMode(BLEND);
}

// 바닥 위 원(step=1) 또는 별 모양(step=2)
void drawFloorRing(float cx, float cz, float rad, float rot, int n, int step) {
  float[][] pts = new float[n][];
  for (int k = 0; k < n; k++) {
    float a = rot + TWO_PI * k / n;
    pts[k] = vtx(cx + cos(a) * rad, 0.005, cz + sin(a) * rad);
    if (pts[k][2] <= NEAR) return;
  }
  for (int k = 0; k < n; k++) {
    float[] a = pts[k], b = pts[(k + step) % n];
    line(sxOf(a), syOf(a), sxOf(b), syOf(b));
  }
}

// ================================================================
//  화면 연출 / HUD
// ================================================================
void makeVignette() {
  vignette = createGraphics(width, height);
  vignetteRed = createGraphics(width, height);
  vignette.beginDraw();    vignette.loadPixels();
  vignetteRed.beginDraw(); vignetteRed.loadPixels();
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      float dx = (x - width * 0.5) / (width * 0.5);
      float dy = (y - height * 0.5) / (height * 0.5);
      float d = sqrt(dx * dx * 0.8 + dy * dy);
      int a = (int) (constrain(pow(max(d - 0.25, 0) / 0.8, 1.4), 0, 1) * 250);
      vignette.pixels[y * width + x] = a << 24;
      vignetteRed.pixels[y * width + x] = (a << 24) | (120 << 16);
    }
  }
  vignette.updatePixels();    vignette.endDraw();
  vignetteRed.updatePixels(); vignetteRed.endDraw();
}

// ---- 공포 연출 ----
void updateHorror(float dt) {
  if (won) { heart = max(0, heart - dt); eyes = null; return; }

  // 어둠 속의 눈: 정면 복도 끝에 나타났다가, 다가가면 사라진다
  if (eyes == null) {
    eyeTimer -= dt;
    if (eyeTimer <= 0) eyeTimer = spawnEyes() ? random(10, 20) : 2;
  } else {
    float dx = eyes[0] - pX, dz = eyes[1] - pZ;
    boolean leave = (eyes[2] -= dt) <= 0 || dx * dx + dz * dz < 3.2 * 3.2;
    eyes[3] = leave ? eyes[3] - dt * 3 : min(1, eyes[3] + dt * 0.6);
    if (leave && eyes[3] <= 0) eyes = null;
  }

  // 심장 박동: 눈이 보이면 빨라지고 강해진다
  float target = (eyes != null) ? 0.4 + 0.6 * max(eyes[3], 0) : 0.12;
  heart = lerp(heart, target, min(1, dt * 1.5));
  heartPhase = (heartPhase + dt / lerp(1.3, 0.6, heart)) % 1.0;

  // 속삭임
  whisperTimer -= dt;
  if (whisperTimer <= 0) {
    whisper = WHISPERS[(int) random(WHISPERS.length)];
    whisperT = 5;
    whisperTimer = random(22, 40);
  }
  whisperT = max(0, whisperT - dt);
}

boolean spawnEyes() {
  IntList cand = new IntList();
  int x = gx, y = gy;
  for (int s = 1; s <= 8; s++) {
    x += DX[gd]; y += DY[gd];
    if (isWall(x, y)) break;
    if (s >= 4) cand.append(s);
  }
  if (cand.size() == 0) return false;
  int s = cand.get((int) random(cand.size()));
  eyes = new float[]{ gx + DX[gd] * s + 0.5, gy + DY[gd] * s + 0.5, random(4, 7), 0, random(1000) };
  return true;
}

void drawEyes() {
  float[] c = vtx(eyes[0], 0.58, eyes[1]);
  if (c[2] < 0.3 || eyes[3] <= 0) return;
  float open = noise(eyes[4], millis() * 0.002) < 0.28 ? 0.1 : 1;   // 깜빡임
  float a = eyes[3] * 255;
  float s = F / c[2];
  float sx = sxOf(c), sy = syOf(c);
  blendMode(ADD);
  noStroke();
  for (int side = -1; side <= 1; side += 2) {
    float ex = sx + side * s * 0.07;
    fill(150, 0, 0, a * 0.18);
    ellipse(ex, sy, s * 0.09, s * 0.06 * open + 1);
    fill(255, 30, 20, a * 0.85);
    ellipse(ex, sy, s * 0.032, s * 0.018 * open + 0.5);
    fill(255, 200, 160, a * 0.6);
    ellipse(ex, sy, s * 0.008, s * 0.006 * open + 0.3);
  }
  blendMode(BLEND);
}

void drawHeartbeat() {
  if (heart < 0.05) return;
  float t = heartPhase;   // 쿵-쿵 두 번 뛰는 박동
  float beat = exp(-sq((t - 0.05) / 0.045)) + 0.7 * exp(-sq((t - 0.22) / 0.045));
  tint(255, 255 * heart * (0.2 + 0.8 * beat));
  image(vignetteRed, 0, 0);
  noTint();
}

void drawGrain() {
  strokeWeight(1);
  for (int k = 0; k < 500; k++) {
    stroke(random(1) < 0.5 ? 0 : 70, random(30, 70));
    point(random(width), random(height));
  }
  noStroke();
}

void drawWhisper() {
  if (whisperT <= 0 || won) return;
  float a = whisperT > 4 ? (5 - whisperT) : min(1, whisperT / 1.5);
  textFont(font);
  textAlign(CENTER, CENTER);
  fill(170, 30, 25, 210 * a);
  text(whisper, width / 2 + random(-0.8, 0.8), height * 0.72 + random(-0.5, 0.5));
}

void resetDust(float[] d, boolean anywhere) {
  d[0] = random(width);
  d[1] = anywhere ? random(height) : height + 5;
  d[2] = random(0.6, 2.4);
  d[3] = random(1000);
}

void drawDust(float dt) {
  blendMode(ADD);
  noStroke();
  for (float[] d : dust) {
    d[1] -= (5 + d[2] * 4) * dt;
    d[0] += sin(millis() * 0.0005 + d[3]) * 8 * dt;
    if (d[1] < -5) resetDust(d, false);
    float a = 22 + 18 * sin(millis() * 0.002 + d[3]);
    fill(170, 170, 180, a * 0.6 * flick);
    ellipse(d[0], d[1], d[2], d[2]);
  }
  blendMode(BLEND);
}

void drawHUD() {
  noStroke();
  // 층 / 걸음 / 시간
  fill(0, 160);
  rect(14, 14, 230, 64, 6);
  textFont(font);
  textAlign(LEFT, TOP);
  fill(230, 180, 110);
  text("지하 미궁  B" + level + "F", 26, 22);
  int sec = ((won ? clearMillis : millis()) - startMillis) / 1000;
  fill(185, 165, 135);
  text("걸음 " + steps + "    시간 " + nf(sec / 60, 2) + ":" + nf(sec % 60, 2), 26, 48);

  // 나침반
  fill(0, 160);
  rect(width / 2 - 70, 14, 140, 44, 6);
  textAlign(CENTER, CENTER);
  fill(115, 100, 80);
  text(DIR_NAME[(gd + 3) % 4], width / 2 - 44, 35);
  text(DIR_NAME[(gd + 1) % 4], width / 2 + 44, 35);
  textFont(fontMid);
  fill(240, 190, 110);
  text(DIR_NAME[gd], width / 2, 33);

  // 안내 문구
  if (hintAlpha > 0) {
    textFont(font);
    textAlign(CENTER, BOTTOM);
    fill(140, 190, 255, hintAlpha);
    text("푸른 빛이 출구다. 어둠 속의 다른 빛은… 믿지 마라.", width / 2, height - 46);
    fill(200, 180, 150, hintAlpha);
    text("W/↑ 전진   S/↓ 후진   A·D / ←→ 회전   Q·E 옆걸음   M 지도   R 새 미궁", width / 2, height - 20);
  }
}

void drawMinimap() {
  float cs = min(7, 230.0 / mw);
  float mx = width - mw * cs - 22, my = 22;
  noStroke();
  fill(12, 9, 6, 200);
  rect(mx - 8, my - 8, mw * cs + 16, mh * cs + 16, 6);
  for (int i = 0; i < mw; i++) for (int j = 0; j < mh; j++) {
    if (!seen[i][j]) continue;
    if (wall[i][j]) fill(62, 52, 42);
    else fill(150, 128, 96, 200);
    rect(mx + i * cs, my + j * cs, cs, cs);
  }
  if (seen[exitX][exitY]) {
    fill(90, 170, 255, 180 + 75 * sin(millis() * 0.006));
    rect(mx + exitX * cs, my + exitY * cs, cs, cs);
  }
  pushMatrix();
  translate(mx + pX * cs, my + pZ * cs);
  rotate(camA);
  fill(255, 190, 90);
  triangle(cs * 0.75, 0, -cs * 0.5, -cs * 0.45, -cs * 0.5, cs * 0.45);
  popMatrix();
}

void drawWin(float dt) {
  winFade = min(1, winFade + dt * 0.7);
  noStroke();
  fill(0, 0, 0, 190 * winFade);
  rect(0, 0, width, height);
  blendMode(ADD);
  for (int k = 8; k >= 1; k--) {
    fill(40, 90, 170, 14 * winFade);
    ellipse(width / 2, height / 2 - 40, 90 * k, 40 * k);
  }
  blendMode(BLEND);

  textAlign(CENTER, CENTER);
  textFont(fontBig);
  fill(160, 215, 255, 255 * winFade);
  text("살아서 빠져나왔다", width / 2, height / 2 - 48);
  textFont(font);
  int sec = (clearMillis - startMillis) / 1000;
  fill(225, 205, 165, 255 * winFade);
  text("걸음 수 " + steps + "     소요 시간 " + nf(sec / 60, 2) + ":" + nf(sec % 60, 2), width / 2, height / 2 + 22);
  fill(180, 160, 130, 255 * winFade);
  text("ENTER  더 깊은 층으로        R  같은 깊이 다시", width / 2, height / 2 + 62);
}

// ---- 한글 폰트 선택 ----
PFont pickFont(int sz) {
  String[] want = { "Malgun Gothic", "맑은 고딕", "Apple SD Gothic Neo", "AppleSDGothicNeo-Regular",
                    "AppleGothic", "NanumGothic", "나눔고딕", "Noto Sans CJK KR", "Noto Sans KR" };
  String[] all = PFont.list();
  for (String w : want) for (String a : all) if (a.equals(w)) return createFont(a, sz, true);
  return createFont("SansSerif", sz, true);
}
