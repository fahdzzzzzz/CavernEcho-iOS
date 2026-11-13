// DiscordEcho: معالج صوت المايك داخل تطبيق (مثل ديسكورد)
//   - تغيير النبرة (pitch) من -12 إلى +12 نغمة + صوت روبوت
//   - صدى "كهف مسكون": تكرار مبعثر (Multi-Tap Delay) + كهف (reverb) مع تحكم كامل:
//       شدة عامة، مضخّم، مدى، شدة الكهف، شدة التكرار، سرعة/تشتيت/عدد التكرارات
//   - موازن ترددات (EQ) للصدى + تغميق الذيل + تنعيم الموجة (modulation)
//   - مودات صدى جاهزة، كل واحد لحاله: ديلاي، ديلاي شريط، غرفة، قاعة، ستاديوم، فضاء
//   - تضخيم الصوت 100%..800% مع حد ناعم
//   - مشغّل أغنية: تتمزج داخل المايك + يطبّق عليها الصدى + تقدر تسمعها أنت (مراقبة)
// يعمل عبر fishhook: يستبدل AudioUnitRender ويعدّل بيانات المايك قبل ما يرسلها التطبيق.

#include <AudioToolbox/AudioToolbox.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "fishhook.h"

#define MAX_RATE 48000
#define MAX_BUFS 2
#define LINE_LEN (MAX_RATE * 4)
#define MUSIC_TMP 8192
#define NCTX (MAX_BUFS + 1)      // قناتين للمايك + واحد للأغنية
#define SONG_CTX MAX_BUFS

// ---------- إعدادات تتغير من القائمة ----------
static volatile int   g_level = 50;     // شدة الصدى 0..100
static volatile int   g_boost = 100;    // مضخّم الصدى 100..400 (%)
static volatile int   g_range = 60;     // مدى الصدى 0..100
static volatile int   g_cave  = 1;      // كهف
static volatile int   g_repeat = 1;     // تكرار
static volatile int   g_cave_amt = 100; // شدة الكهف 0..100
static volatile int   g_rep_amt = 100;  // شدة التكرار 0..100
static volatile int   g_tap_speed = 100;// سرعة/تردد التكرار 50..300 (%)  (أكبر = أبطأ وأبعد)
static volatile int   g_tap_fb = 60;    // عدد التكرارات 0..100
static volatile int   g_tap_scatter = 100; // التبعثر 0..100 (0 = منتظم، 100 = مبعثر زي الكرت)
static volatile int   g_damp = 40;      // تغميق الذيل 0..100
static volatile int   g_mod = 50;       // تنعيم الموجة 0..100
static volatile int   g_eq_lo_f = 200;  // تردد حد الجهير (Hz)
static volatile int   g_eq_hi_f = 3500; // تردد حد الحاد (Hz)
static volatile int   g_eq_lo = 100;    // قوة الجهير 0..200 (%)
static volatile int   g_eq_mid = 100;   // قوة الوسط 0..200 (%)
static volatile int   g_eq_hi = 100;    // قوة الحاد 0..200 (%)
static volatile int   g_mode = 0;       // 0 = كهف مسكون (حسب الأزرار)، 1..6 = مودات جاهزة
static volatile int   g_song_echo = 1;  // تطبيق الصدى على الأغنية
static volatile int   g_monitor = 0;    // أنت تسمع الأغنية
static volatile int   g_mon_vol = 100;  // مستوى المراقبة 0..200
static volatile int   g_gain  = 100;    // تضخيم الصوت 100..800 (%)
static volatile int   g_pitch = 0;      // نغمات -12..12
static volatile int   g_robot = 0;      // 0/1
static volatile int   g_voice_mute = 0; // كتم صوتي أثناء الأغنية
static volatile float g_peak  = 0.0f;   // مستوى المايك 0..1

static int clampi(int v, int a, int b) { return v < a ? a : (v > b ? b : v); }

void DiscordEcho_SetLevel(int v)  { g_level = clampi(v, 0, 100); }
void DiscordEcho_SetEchoBoost(int v) { g_boost = clampi(v, 100, 400); }
void DiscordEcho_SetRange(int v)  { g_range = clampi(v, 0, 100); }
void DiscordEcho_SetCave(int on)  { g_cave = on ? 1 : 0; }
void DiscordEcho_SetRepeat(int on){ g_repeat = on ? 1 : 0; }
void DiscordEcho_SetCaveAmount(int v) { g_cave_amt = clampi(v, 0, 100); }
void DiscordEcho_SetRepeatAmount(int v) { g_rep_amt = clampi(v, 0, 100); }
void DiscordEcho_SetTapSpeed(int v) { g_tap_speed = clampi(v, 50, 300); }
void DiscordEcho_SetTapFeedback(int v) { g_tap_fb = clampi(v, 0, 100); }
void DiscordEcho_SetTapScatter(int v) { g_tap_scatter = clampi(v, 0, 100); }
void DiscordEcho_SetDamp(int v)   { g_damp = clampi(v, 0, 100); }
void DiscordEcho_SetMod(int v)    { g_mod = clampi(v, 0, 100); }
void DiscordEcho_SetEqLoFreq(int v) { g_eq_lo_f = clampi(v, 60, 800); }
void DiscordEcho_SetEqHiFreq(int v) { g_eq_hi_f = clampi(v, 1500, 9000); }
void DiscordEcho_SetEqLo(int v)   { g_eq_lo = clampi(v, 0, 200); }
void DiscordEcho_SetEqMid(int v)  { g_eq_mid = clampi(v, 0, 200); }
void DiscordEcho_SetEqHi(int v)   { g_eq_hi = clampi(v, 0, 200); }
void DiscordEcho_SetMode(int v)   { g_mode = clampi(v, 0, 6); }
void DiscordEcho_SetSongEcho(int on) { g_song_echo = on ? 1 : 0; }
void DiscordEcho_SetMonitor(int on) { g_monitor = on ? 1 : 0; }
void DiscordEcho_SetMonitorVolume(int v) { g_mon_vol = clampi(v, 0, 200); }
void DiscordEcho_SetGain(int v)   { g_gain = clampi(v, 100, 800); }
void DiscordEcho_SetPitch(int v)  { g_pitch = clampi(v, -12, 12); }
void DiscordEcho_SetRobot(int on) { g_robot = on ? 1 : 0; }
void DiscordEcho_SetVoiceMute(int on) { g_voice_mute = on ? 1 : 0; }
float DiscordEcho_GetPeak(void)   { return g_peak; }

// ---------- حد ناعم: يرفع الصوت بدون ما يقطعه ----------
static float soft_limit(float y) {
    float a = y < 0 ? -y : y;
    if (a <= 0.6f) return y;
    float s = 0.6f + 0.4f * tanhf((a - 0.6f) / 0.4f);
    return y < 0 ? -s : s;
}

// ---------- كهف (reverb): 8 مرشحات comb + 4 allpass، مع تموّج بسيط يكسر الرنين ----------
#define RV_COMBS    8
#define RV_APS      4
#define RV_COMB_MAX 16384   // لازم يكون من مضاعفات 2
#define RV_AP_MAX   2048

typedef struct {
    float comb[RV_COMBS][RV_COMB_MAX];
    float damp[RV_COMBS];
    unsigned cpos[RV_COMBS];
    float lph[RV_COMBS];
    int inited;
    float ap[RV_APS][RV_AP_MAX];
    unsigned apos[RV_APS];
} Reverb;

static const int kCombBase[RV_COMBS] = {1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617};
static const int kApBase[RV_APS] = {556, 441, 341, 225};

// ---------- بارامترات الصدى (تتحسب مرة لكل دفعة) ----------
typedef struct {
    int kind;                 // 0 = كهف+تكرار مبعثر، 1 = ديلاي بسيط، 2 = ريفيرب فقط
    int rep, cave, tape;
    size_t tapD[8];
    float tapG[8];
    float fbk;
    float rep_gain;
    size_t dD;
    float d_fb, d_gain;
    int clen[RV_COMBS], alen[RV_APS];
    float cave_fb, damp, cave_wet;
    float mod_depth;
    float lfo_inc[RV_COMBS];
    float eq_a1, eq_a2, eq_gl, eq_gm, eq_gh;
    float wet_gain;
} EchoParams;

typedef struct {
    float line[LINE_LEN];
    size_t pos;
    float tape;
    float eq_lo, eq_lp2;
    Reverb rv;
} EchoCtx;

static EchoCtx g_ctx[NCTX];
static int g_cleared[NCTX];

static float rv_process(Reverb *rv, float x, const EchoParams *P) {
    float in = x * 0.015f;
    float acc = 0.0f;
    if (!rv->inited) {
        for (int c = 0; c < RV_COMBS; c++) rv->lph[c] = 0.8f * (float)c;
        rv->inited = 1;
    }
    for (int c = 0; c < RV_COMBS; c++) {
        unsigned w = rv->cpos[c] & (RV_COMB_MAX - 1);
        float dly = (float)P->clen[c];
        if (P->mod_depth > 0.0f) {
            rv->lph[c] += P->lfo_inc[c];
            if (rv->lph[c] > 6.2831853f) rv->lph[c] -= 6.2831853f;
            dly += P->mod_depth * sinf(rv->lph[c]);
        }
        float rpos = (float)w - dly;
        if (rpos < 0.0f) rpos += (float)RV_COMB_MAX;
        unsigned i0 = (unsigned)rpos;
        float fr = rpos - (float)i0;
        float a = rv->comb[c][i0 & (RV_COMB_MAX - 1)];
        float b = rv->comb[c][(i0 + 1u) & (RV_COMB_MAX - 1)];
        float out = a + fr * (b - a);
        rv->damp[c] = out * (1.0f - P->damp) + rv->damp[c] * P->damp;
        rv->comb[c][w] = in + rv->damp[c] * P->cave_fb;
        rv->cpos[c] = (w + 1u) & (RV_COMB_MAX - 1);
        acc += out;
    }
    for (int a = 0; a < RV_APS; a++) {
        unsigned p = rv->apos[a];
        if (p >= (unsigned)P->alen[a]) p = 0;
        float b = rv->ap[a][p];
        float out = b - acc;
        rv->ap[a][p] = acc + b * 0.5f;
        if (++p >= (unsigned)P->alen[a]) p = 0;
        rv->apos[a] = p;
        acc = out;
    }
    return acc;
}

static void echo_params(EchoParams *P, float rate, UInt32 chans) {
    memset(P, 0, sizeof(*P));
    int lvl = g_level, mode = g_mode;
    float r = (float)g_range / 100.0f;
    float ch = (float)chans;
    float rs = rate / 44100.0f;

    P->rep = g_repeat;
    P->cave = g_cave;
    P->wet_gain = ((float)lvl / 100.0f) * ((float)g_boost / 100.0f);

    // ----- مودات جاهزة -----
    float size = 1.4f + 1.8f * r;
    float fb = 0.84f + 0.14f * r;
    float cwet = 3.0f * (float)g_cave_amt / 100.0f;
    P->kind = 0;
    if (mode == 1 || mode == 2) {
        P->kind = 1;
        P->tape = (mode == 2);
    } else if (mode >= 3) {
        static const float kSize[7] = {0, 0, 0, 0.45f, 1.2f, 2.4f, 3.2f};
        static const float kFb[7]   = {0, 0, 0, 0.76f, 0.90f, 0.955f, 0.975f};
        static const float kWet[7]  = {0, 0, 0, 2.2f, 2.8f, 3.0f, 3.0f};
        P->kind = 2;
        size = kSize[mode] * (0.8f + 0.4f * r);
        fb = kFb[mode] + (r - 0.6f) * 0.04f;
        cwet = kWet[mode];
    }
    if (fb > 0.985f) fb = 0.985f;
    P->cave_fb = fb;
    P->cave_wet = cwet;

    // ----- ريفيرب -----
    float dampc = 0.05f + 0.0085f * (float)g_damp;   // 0.05 .. 0.90
    P->damp = dampc;
    for (int c = 0; c < RV_COMBS; c++) {
        int L = (int)((float)kCombBase[c] * rs * size) * (int)chans;
        if (L < 8) L = 8;
        if (L > RV_COMB_MAX - 160) L = RV_COMB_MAX - 160;
        P->clen[c] = L;
    }
    for (int a = 0; a < RV_APS; a++) {
        int L = (int)((float)kApBase[a] * rs) * (int)chans;
        P->alen[a] = L < 1 ? 1 : (L >= RV_AP_MAX ? RV_AP_MAX - 1 : L);
    }
    P->mod_depth = (float)g_mod / 100.0f * 24.0f * ch;
    for (int c = 0; c < RV_COMBS; c++) {
        float hz = 0.35f + 0.17f * (float)c;
        P->lfo_inc[c] = 6.2831853f * hz / (rate * ch);
    }

    // ----- تكرار مبعثر (Multi-Tap): أزمنة غير منتظمة مثل كرت EAX -----
    static const float kTapT[8] = {0.020f, 0.062f, 0.0925f, 0.1305f, 0.160f, 0.178f, 0.3044f, 0.3715f};
    static const float kTapG[8] = {0.55f, 0.50f, 0.50f, 0.70f, 0.60f, 0.50f, 0.55f, 0.45f};
    float sc = (float)g_tap_scatter / 100.0f;
    float tscale = ((float)g_tap_speed / 100.0f) * (0.8f + 0.8f * r);
    for (int k = 0; k < 8; k++) {
        float reg = 0.0465f * (float)(k + 1);          // منتظم
        float t = (kTapT[k] * sc + reg * (1.0f - sc)) * tscale;
        size_t d = (size_t)(t * rate) * chans;
        if (d < 1) d = 1;
        if (d >= LINE_LEN) d = LINE_LEN - 1;
        P->tapD[k] = d;
        P->tapG[k] = kTapG[k];
    }
    float tf = (float)g_tap_fb / 100.0f;
    float fbk = 0.25f + 0.70f * tf + 0.03f * r;        // أقصى 0.98
    if (fbk > 0.98f) fbk = 0.98f;
    P->fbk = fbk;
    P->rep_gain = 1.2f * 0.45f * (float)g_rep_amt / 100.0f;

    // ----- ديلاي بسيط / شريط -----
    {
        float t = 0.30f * ((float)g_tap_speed / 100.0f) * (0.7f + 0.6f * r);
        size_t d = (size_t)(t * rate) * chans;
        if (d < 1) d = 1;
        if (d >= LINE_LEN) d = LINE_LEN - 1;
        P->dD = d;
        P->d_fb = 0.25f + 0.65f * tf;
        P->d_gain = 1.0f;
    }

    // ----- موازن ترددات على الصدى -----
    float fs = rate * ch;
    float flo = (float)g_eq_lo_f, fhi = (float)g_eq_hi_f;
    if (fhi < flo * 1.5f) fhi = flo * 1.5f;
    P->eq_a1 = 1.0f - expf(-6.2831853f * flo / fs);
    P->eq_a2 = 1.0f - expf(-6.2831853f * fhi / fs);
    P->eq_gl = (float)g_eq_lo / 100.0f;
    P->eq_gm = (float)g_eq_mid / 100.0f;
    P->eq_gh = (float)g_eq_hi / 100.0f;
}

static float echo_run(EchoCtx *c, float y, const EchoParams *P) {
    float wet = 0.0f;
    if (P->kind == 0) {
        float rin = y;
        if (P->rep) {
            size_t p = c->pos;
            if (p >= LINE_LEN) p = 0;
            float dsum = 0.0f;
            float q[8];
            for (int k = 0; k < 8; k++) {
                size_t i = p >= P->tapD[k] ? p - P->tapD[k] : p + LINE_LEN - P->tapD[k];
                q[k] = c->line[i];
                dsum += q[k] * P->tapG[k];
            }
            c->line[p] = y + P->fbk * (0.38f * q[4] + 0.33f * q[6] + 0.29f * q[7]);
            wet += dsum * P->rep_gain;
            rin = y + 0.3f * dsum;               // الكهف يسمع التكرارات كمان
            if (++p >= LINE_LEN) p = 0;
            c->pos = p;
        }
        if (P->cave) wet += rv_process(&c->rv, rin, P) * P->cave_wet;
    } else if (P->kind == 1) {
        size_t p = c->pos;
        if (p >= LINE_LEN) p = 0;
        size_t i = p >= P->dD ? p - P->dD : p + LINE_LEN - P->dD;
        float d = c->line[i];
        float fbin = d;
        if (P->tape) { c->tape += 0.35f * (d - c->tape); fbin = c->tape; }
        c->line[p] = y + P->d_fb * fbin;
        wet += d * P->d_gain;
        if (++p >= LINE_LEN) p = 0;
        c->pos = p;
    } else {
        wet += rv_process(&c->rv, y, P) * P->cave_wet;
    }
    // موازن الترددات
    c->eq_lo  += P->eq_a1 * (wet - c->eq_lo);
    c->eq_lp2 += P->eq_a2 * (wet - c->eq_lp2);
    float lo = c->eq_lo, lp2 = c->eq_lp2;
    return lo * P->eq_gl + (lp2 - lo) * P->eq_gm + (wet - lp2) * P->eq_gh;
}

static void clear_ctx(int idx) { memset(&g_ctx[idx], 0, sizeof(g_ctx[idx])); }

// ---------- مغيّر النبرة (خط تأخير بنافذتين متداخلتين) ----------
#define PS_WIN 2048
#define PS_BUF 4096   // لازم يكون من مضاعفات 2 وأكبر من PS_WIN + 2

typedef struct {
    float buf[PS_BUF];
    unsigned w;
    float d;
} PitchShifter;

static PitchShifter g_ps[MAX_BUFS];
static int g_ps_on[MAX_BUFS];
static float g_win[1025];
static float g_robot_phase;

static float ps_tap(const PitchShifter *ps, float d) {
    int di = (int)d;
    float fr = d - (float)di;
    float a = ps->buf[(ps->w - (unsigned)di) & (PS_BUF - 1)];
    float b = ps->buf[(ps->w - (unsigned)di - 1u) & (PS_BUF - 1)];
    return a + fr * (b - a);
}

static float ps_process(PitchShifter *ps, float x, float ratio) {
    ps->buf[ps->w & (PS_BUF - 1)] = x;
    float d1 = ps->d;
    float d2 = d1 + PS_WIN * 0.5f;
    if (d2 >= PS_WIN) d2 -= PS_WIN;
    float y = g_win[(int)(d1 * (1024.0f / PS_WIN))] * ps_tap(ps, d1)
            + g_win[(int)(d2 * (1024.0f / PS_WIN))] * ps_tap(ps, d2);
    ps->w++;
    ps->d += 1.0f - ratio;
    if (ps->d >= PS_WIN) ps->d -= PS_WIN;
    if (ps->d < 0.0f) ps->d += PS_WIN;
    return y;
}

// ---------- مشغّل الأغنية (مخزّنة كعينات أحادية 48kHz) ----------
typedef struct { float *data; size_t len; } MusicSlot;
static MusicSlot g_mslot[2];
static volatile int    g_mcur = -1;      // الخانة المستخدمة حالياً (-1 = ما فيه)
static volatile int    g_mplaying = 0;
static volatile int    g_mloop = 0;
static volatile int    g_mvol = 100;     // 0..200 (%)
static volatile double g_mpos = 0.0;     // موضع التشغيل بالعينات
static volatile double g_mseek = -1.0;   // طلب قفز (-1 = ما فيه)
static float g_mtmp[MUSIC_TMP];
static float g_sout[MUSIC_TMP];

// تأخذ ملكية المصفوفة (malloc). تتحرر لما تتحمّل أغنية ثانية.
int DiscordEcho_MusicLoad(float *samples, size_t count) {
    if (!samples || count < 2) return 0;
    int next = (g_mcur == 0) ? 1 : 0;
    g_mplaying = 0;
    free(g_mslot[next].data);
    g_mslot[next].data = samples;
    g_mslot[next].len = count;
    g_mpos = 0.0;
    g_mseek = -1.0;
    __sync_synchronize();
    g_mcur = next;
    return 1;
}
void DiscordEcho_MusicPlay(int play) { if (g_mcur >= 0) g_mplaying = play ? 1 : 0; }
void DiscordEcho_MusicStop(void) { g_mplaying = 0; g_mseek = 0.0; g_mpos = 0.0; }
void DiscordEcho_MusicSeek(float frac) {
    int cur = g_mcur;
    if (cur < 0) return;
    if (frac < 0.0f) frac = 0.0f;
    if (frac > 1.0f) frac = 1.0f;
    g_mseek = (double)frac * (double)g_mslot[cur].len;
}
void DiscordEcho_MusicSetVolume(int pct) { g_mvol = clampi(pct, 0, 200); }
void DiscordEcho_MusicSetLoop(int on) { g_mloop = on ? 1 : 0; }
int  DiscordEcho_MusicIsPlaying(void) { return g_mplaying; }
float DiscordEcho_MusicProgress(void) {
    int cur = g_mcur;
    if (cur < 0 || g_mslot[cur].len < 2) return 0.0f;
    double p = g_mpos / (double)g_mslot[cur].len;
    return (float)(p < 0 ? 0 : (p > 1 ? 1 : p));
}
float DiscordEcho_MusicDuration(void) {
    int cur = g_mcur;
    return cur < 0 ? 0.0f : (float)((double)g_mslot[cur].len / 48000.0);
}

// تولّد عينات الأغنية لهذي الدفعة (بمعدل المايك). ترجع 1 إذا فيه أغنية تشتغل.
static int music_generate(float *out, UInt32 frames, float rate) {
    int cur = g_mcur;
    if (cur < 0 || frames == 0 || frames > MUSIC_TMP) return 0;
    const float *d = g_mslot[cur].data;
    size_t len = g_mslot[cur].len;
    if (!d || len < 2) return 0;
    if (g_mseek >= 0.0) {
        double s = g_mseek;
        if (s > (double)(len - 2)) s = (double)(len - 2);
        g_mpos = s;
        g_mseek = -1.0;
    }
    if (!g_mplaying) return 0;
    if (rate < 8000.0f) rate = 48000.0f;
    double step = 48000.0 / (double)rate;
    double pos = g_mpos;
    float vol = (float)g_mvol / 100.0f;
    int loop = g_mloop;
    int on = 1;
    for (UInt32 i = 0; i < frames; i++) {
        float m = 0.0f;
        if (on) {
            if (pos >= (double)(len - 1)) {
                if (loop) { pos = 0.0; }
                else { on = 0; g_mplaying = 0; pos = 0.0; }
            }
            if (on) {
                size_t i0 = (size_t)pos;
                float fr = (float)(pos - (double)i0);
                m = d[i0] + fr * (d[i0 + 1] - d[i0]);
                pos += step;
            }
        }
        out[i] = m * vol;
    }
    g_mpos = pos;
    return 1;
}

// ---------- مراقبة: تسمع الأغنية (مع الصدى) بنفسك ----------
#define MON_LEN (1 << 17)   // لازم يكون من مضاعفات 2
static float g_mon[MON_LEN];
static volatile unsigned g_mon_w = 0, g_mon_r = 0;
static volatile float g_mon_rate = 48000.0f;
static double g_mon_frac = 0.0;

static void mon_write(const float *src, UInt32 frames, float rate, float vol) {
    g_mon_rate = rate;
    unsigned w = g_mon_w;
    for (UInt32 i = 0; i < frames; i++) {
        g_mon[w & (MON_LEN - 1)] = src ? src[i] * vol : 0.0f;
        w++;
    }
    __sync_synchronize();
    g_mon_w = w;
}

// يستدعيها مشغّل المراقبة (خيط الصوت). تعبّي out بعدد n عينة بمعدل outRate.
void DiscordEcho_MonitorRead(float *out, unsigned n, double outRate) {
    double step = (double)g_mon_rate / (outRate > 1000.0 ? outRate : 48000.0);
    unsigned w = g_mon_w, r = g_mon_r;
    unsigned avail = w - r;
    // لو متأخر كثير، نرجع قريب من الحاضر
    unsigned maxLag = (unsigned)(g_mon_rate * 0.5f);
    if (avail > maxLag) { r = w - (unsigned)(g_mon_rate * 0.1f); avail = w - r; g_mon_frac = 0.0; }
    for (unsigned i = 0; i < n; i++) {
        if (avail < 3) { out[i] = 0.0f; continue; }
        float a = g_mon[r & (MON_LEN - 1)];
        float b = g_mon[(r + 1) & (MON_LEN - 1)];
        out[i] = a + (float)g_mon_frac * (b - a);
        g_mon_frac += step;
        while (g_mon_frac >= 1.0) { g_mon_frac -= 1.0; r++; avail--; if (avail < 3) break; }
    }
    __sync_synchronize();
    g_mon_r = r;
}

// ---------- الهوك ----------
static AudioUnit g_unit;
static AudioStreamBasicDescription g_fmt;
static int g_have_fmt;
static int g_song_cleared = 1;
static float g_stail = 0.0f;

static OSStatus (*orig_render)(AudioUnit, AudioUnitRenderActionFlags *,
                               const AudioTimeStamp *, UInt32, UInt32,
                               AudioBufferList *);

static void update_peak(float pk) {
    float prev = g_peak * 0.8f;
    g_peak = pk > prev ? pk : prev;
}

static int echo_enabled(void) {
    return g_level > 0 && (g_mode > 0 || g_cave || g_repeat);
}

static void process_buffer(int idx, AudioBuffer *ab, const float *mus, UInt32 mus_frames) {
    int is_float = (g_fmt.mFormatFlags & kAudioFormatFlagIsFloat) != 0;
    UInt32 bits = g_fmt.mBitsPerChannel;
    if (!((is_float && bits == 32) || (!is_float && bits == 16))) return;

    UInt32 bytes_per = bits / 8;
    size_t n = ab->mDataByteSize / bytes_per;
    UInt32 chans = ab->mNumberChannels ? ab->mNumberChannels : 1;

    int gn = g_gain;
    int semis = g_pitch;

    int echo_on = echo_enabled();
    int ps_on = (semis != 0) && chans == 1;     // النبرة والروبوت للمايك الأحادي فقط
    int robot_on = g_robot && chans == 1;
    int mute = g_voice_mute && mus != NULL;
    int changed = echo_on || ps_on || robot_on || gn != 100 || mus != NULL;

    // لا شي مفعّل: بس نقيس المستوى ونخلي الصوت يمر كما هو
    if (!changed) {
        float pk = 0.0f;
        for (size_t i = 0; i < n; i++) {
            float x = is_float ? ((float *)ab->mData)[i]
                               : ((int16_t *)ab->mData)[i] / 32768.0f;
            float a = x < 0 ? -x : x;
            if (a > pk) pk = a;
        }
        update_peak(pk);
        if (!g_cleared[idx]) { clear_ctx(idx); g_cleared[idx] = 1; }
        g_ps_on[idx] = 0;
        return;
    }

    if (!echo_on) {
        if (!g_cleared[idx]) { clear_ctx(idx); g_cleared[idx] = 1; }
    } else {
        g_cleared[idx] = 0;
    }

    PitchShifter *ps = &g_ps[idx];
    if (ps_on) {
        if (!g_ps_on[idx]) { memset(ps, 0, sizeof(*ps)); g_ps_on[idx] = 1; }
    } else {
        g_ps_on[idx] = 0;
    }

    float rate = (float)g_fmt.mSampleRate;
    if (rate < 8000.0f) rate = 48000.0f;

    float gain = (float)gn / 100.0f;
    float ratio = powf(2.0f, (float)semis / 12.0f);
    float rstep = 6.2831853f * 70.0f / rate;

    EchoParams P;
    if (echo_on) echo_params(&P, rate, chans);
    EchoCtx *ctx = &g_ctx[idx];

    float pk = 0.0f;
    UInt32 ch = 0;
    size_t fi = 0;
    for (size_t i = 0; i < n; i++) {
        float x = is_float ? ((float *)ab->mData)[i]
                           : ((int16_t *)ab->mData)[i] / 32768.0f;
        float y = mute ? 0.0f : x;

        if (ps_on) y = ps_process(ps, y, ratio);

        if (robot_on) {
            y *= 1.4f * sinf(g_robot_phase);
            g_robot_phase += rstep;
            if (g_robot_phase > 6.2831853f) g_robot_phase -= 6.2831853f;
        }

        if (echo_on) y = y + echo_run(ctx, y, &P) * P.wet_gain;

        y = soft_limit(y * gain);

        float a = y < 0 ? -y : y;
        if (a > pk) pk = a;

        if (mus && fi < mus_frames) y = soft_limit(y + mus[fi]);

        if (is_float) ((float *)ab->mData)[i] = y;
        else          ((int16_t *)ab->mData)[i] = (int16_t)(y * 32767.0f);

        if (++ch >= chans) { ch = 0; fi++; }
    }
    update_peak(pk);
}

static OSStatus my_render(AudioUnit unit, AudioUnitRenderActionFlags *flags,
                          const AudioTimeStamp *ts, UInt32 bus,
                          UInt32 frames, AudioBufferList *io) {
    OSStatus st = orig_render(unit, flags, ts, bus, frames, io);
    if (st != noErr || bus != 1 || io == NULL) return st;   // bus 1 = المايك

    if (unit != g_unit || !g_have_fmt) {
        UInt32 sz = sizeof(g_fmt);
        if (AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat,
                                 kAudioUnitScope_Output, 1, &g_fmt, &sz) == noErr) {
            g_unit = unit;
            g_have_fmt = 1;
        } else {
            g_have_fmt = 0;
            return st;
        }
    }

    float rate = (float)g_fmt.mSampleRate;
    if (rate < 8000.0f) rate = 48000.0f;

    // ----- الأغنية: تمر على صدى خاص فيها، وبعدين تنزل للمايك وللمراقبة -----
    int mus_on = music_generate(g_mtmp, frames, rate);
    int have_song = 0;
    if (frames <= MUSIC_TMP) {
        int s_echo = echo_enabled() && g_song_echo;
        if (mus_on) g_stail = 8.0f * rate;
        if (!s_echo) g_stail = mus_on ? g_stail : 0.0f;
        if (mus_on || g_stail > 0.0f) {
            if (s_echo) {
                EchoParams SP;
                echo_params(&SP, rate, 1);
                EchoCtx *sc = &g_ctx[SONG_CTX];
                g_song_cleared = 0;
                for (UInt32 i = 0; i < frames; i++) {
                    float s = mus_on ? g_mtmp[i] : 0.0f;
                    g_sout[i] = soft_limit(s + echo_run(sc, s, &SP) * SP.wet_gain);
                }
            } else {
                for (UInt32 i = 0; i < frames; i++) g_sout[i] = mus_on ? g_mtmp[i] : 0.0f;
            }
            if (!mus_on) g_stail -= (float)frames;
            have_song = 1;
        } else if (!g_song_cleared) {
            clear_ctx(SONG_CTX);
            g_song_cleared = 1;
        }
        if (g_monitor) mon_write(have_song ? g_sout : NULL, frames, rate, (float)g_mon_vol / 100.0f);
    }

    for (UInt32 b = 0; b < io->mNumberBuffers && b < MAX_BUFS; b++) {
        if (io->mBuffers[b].mData)
            process_buffer((int)b, &io->mBuffers[b], have_song ? g_sout : NULL, frames);
    }
    return st;
}

__attribute__((constructor))
static void init(void) {
    for (int i = 0; i <= 1024; i++) {
        float s = sinf(3.14159265f * (float)i / 1024.0f);
        g_win[i] = s * s;
    }
    struct rebinding r = { "AudioUnitRender", (void *)my_render, (void **)&orig_render };
    rebind_symbols(&r, 1);
}
