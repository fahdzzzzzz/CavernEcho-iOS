// DiscordEchoUI: قائمة عائمة بتصميم Creative EAX Console وأربعة تبويبات (الصدى، النبرة، المضخّم، الأغاني)

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers>
#include <math.h>
#include <stdlib.h>

extern void DiscordEcho_SetEnableEffects(int on);
extern void DiscordEcho_SetEffectsAmount(int v);
extern void DiscordEcho_SetPreset(int preset);
extern void DiscordEcho_SetGain(int v);
extern void DiscordEcho_SetPitch(int v);
extern void DiscordEcho_SetRobot(int on);
extern void DiscordEcho_SetVoiceMute(int on);
extern float DiscordEcho_GetPeak(void);
extern int   DiscordEcho_MusicLoad(float *samples, size_t count);
extern void  DiscordEcho_MusicPlay(int play);
extern void  DiscordEcho_MusicStop(void);
extern void  DiscordEcho_MusicSeek(float frac);
extern void  DiscordEcho_MusicSetVolume(int pct);
extern void  DiscordEcho_MusicSetLoop(int on);
extern int   DiscordEcho_MusicIsPlaying(void);
extern float DiscordEcho_MusicProgress(void);
extern float DiscordEcho_MusicDuration(void);

static NSString *const kEffectsKey    = @"DiscordEchoEnableEffects";
static NSString *const kAmountKey     = @"DiscordEchoEffectsAmount";
static NSString *const kPresetKey     = @"DiscordEchoPreset";
static NSString *const kGainKey       = @"DiscordEchoGain";
static NSString *const kPitchKey      = @"DiscordEchoPitch";
static NSString *const kRobotKey      = @"DiscordEchoRobot";
static NSString *const kMusicVolKey   = @"DiscordEchoMusicVol";
static NSString *const kMusicLoopKey  = @"DiscordEchoMusicLoop";
static NSString *const kMuteKey       = @"DiscordEchoVoiceMute";

static const CGFloat kPanelW = 320;
static const CGFloat kPanelH = 396;
static const CGFloat kTabTop = 56;

static int EchoInt(NSString *key, int def) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    return [d objectForKey:key] ? (int)[d integerForKey:key] : def;
}

#pragma mark - فك ترميز الأغنية

static const double kTargetRate = 48000.0;
static const size_t kMaxSamples = 48000 * 60 * 8;

static float *EchoDecodeFile(NSURL *url, size_t *outCount, BOOL *truncated) {
    *outCount = 0;
    *truncated = NO;
    NSError *err = nil;
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:&err];
    if (!file) return NULL;
    AVAudioFormat *src = file.processingFormat;
    AVAudioChannelCount chans = src.channelCount;
    if (chans < 1 || src.sampleRate <= 0) return NULL;
    AVAudioFormat *dst = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                          sampleRate:kTargetRate
                                                            channels:chans
                                                         interleaved:NO];
    if (!dst) return NULL;
    AVAudioConverter *conv = [[AVAudioConverter alloc] initFromFormat:src toFormat:dst];
    if (!conv) return NULL;

    double est = (double)file.length * kTargetRate / src.sampleRate + 8192.0;
    size_t cap = est > (double)kMaxSamples ? kMaxSamples : (size_t)est;
    float *out = (float *)malloc(cap * sizeof(float));
    if (!out) return NULL;
    size_t n = 0;

    const AVAudioFrameCount chunk = 4096;
    AVAudioPCMBuffer *outBuf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:dst frameCapacity:chunk];
    BOOL finished = NO;
    while (!finished && n < cap) {
        NSError *cerr = nil;
        AVAudioConverterOutputStatus st = [conv convertToBuffer:outBuf
                                                          error:&cerr
                                             withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount inNum, AVAudioConverterInputStatus *status) {
            AVAudioFramePosition remain = file.length - file.framePosition;
            if (remain <= 0 || inNum == 0) {
                *status = AVAudioConverterInputStatus_EndOfStream;
                return nil;
            }
            AVAudioFrameCount want = inNum;
            if ((AVAudioFramePosition)want > remain) want = (AVAudioFrameCount)remain;
            AVAudioPCMBuffer *inBuf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:src frameCapacity:want];
            NSError *rerr = nil;
            if (![file readIntoBuffer:inBuf frameCount:want error:&rerr] || inBuf.frameLength == 0) {
                *status = AVAudioConverterInputStatus_EndOfStream;
                return nil;
            }
            *status = AVAudioConverterInputStatus_HaveData;
            return inBuf;
        }];
        if (st == AVAudioConverterOutputStatus_Error) break;
        if (st == AVAudioConverterOutputStatus_EndOfStream ||
            st == AVAudioConverterOutputStatus_InputRanDry) finished = YES;

        AVAudioFrameCount got = outBuf.frameLength;
        float *const *chData = outBuf.floatChannelData;
        for (AVAudioFrameCount i = 0; i < got && n < cap; i++) {
            float s = 0;
            for (AVAudioChannelCount c = 0; c < chans; c++) s += chData[c][i];
            out[n++] = s / (float)chans;
        }
        if (got == 0) finished = YES;
    }
    if (!finished && n >= cap && cap == kMaxSamples) *truncated = YES;
    if (n < 2) { free(out); return NULL; }
    *outCount = n;
    return out;
}

static NSString *EchoTime(float s) {
    int t = (int)lroundf(s < 0 ? 0 : s);
    return [NSString stringWithFormat:@"%d:%02d", t / 60, t % 60];
}

#pragma mark - نافذة شفافة

@interface EchoWindow : UIWindow
@end

@implementation EchoWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v == self || v == self.rootViewController.view) return nil;
    return v;
}
@end

#pragma mark - وحدة التحكم

@interface EchoController : UIViewController <UIDocumentPickerDelegate>
@property (nonatomic, strong) UIButton *fab;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UISegmentedControl *tabs;
@property (nonatomic, strong) NSArray<UIView *> *tabViews;
// تبويب الصدى (EAX Console)
@property (nonatomic, strong) UISwitch *effectsSwitch;
@property (nonatomic, strong) UISegmentedControl *presetSeg;
@property (nonatomic, strong) UILabel *amountLabel;
@property (nonatomic, strong) UISlider *amountSlider;
// النبرة
@property (nonatomic, strong) UILabel *pitchLabel;
@property (nonatomic, strong) UISlider *pitchSlider;
@property (nonatomic) BOOL robot;
// المضخّم
@property (nonatomic, strong) UILabel *gainLabel;
@property (nonatomic, strong) UISlider *gainSlider;
@property (nonatomic, strong) UIProgressView *meter;
// الأغاني
@property (nonatomic, strong) UILabel *songLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UISlider *seekSlider;
@property (nonatomic, strong) UIButton *playBtn;
@property (nonatomic, strong) UILabel *volLabel;
@property (nonatomic, strong) UISlider *volSlider;
@property (nonatomic) BOOL seeking;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation EchoController

- (UILabel *)makeLabelAt:(CGRect)frame size:(CGFloat)size bold:(BOOL)bold alpha:(CGFloat)alpha {
    UILabel *l = [[UILabel alloc] initWithFrame:frame];
    l.textAlignment = NSTextAlignmentCenter;
    l.textColor = [UIColor colorWithWhite:1 alpha:alpha];
    l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    l.numberOfLines = 0;
    return l;
}

- (UIButton *)makeButton:(NSString *)title frame:(CGRect)f tag:(NSInteger)tag action:(SEL)a {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = f;
    b.tag = tag;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
    b.layer.cornerRadius = 10;
    [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UISlider *)makeSliderAt:(CGRect)f min:(float)mn max:(float)mx value:(float)v action:(SEL)a {
    UISlider *s = [[UISlider alloc] initWithFrame:f];
    s.minimumValue = mn;
    s.maximumValue = mx;
    s.continuous = YES;
    s.value = v;
    [s addTarget:self action:a forControlEvents:UIControlEventValueChanged];
    return s;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    int enableEffects = EchoInt(kEffectsKey, 1);
    int amount        = EchoInt(kAmountKey, 50);
    int preset        = EchoInt(kPresetKey, 0);
    int gain          = EchoInt(kGainKey, 100);
    int pitch         = EchoInt(kPitchKey, 0);
    self.robot        = EchoInt(kRobotKey, 0) != 0;
    int mvol          = EchoInt(kMusicVolKey, 100);
    int mloop         = EchoInt(kMusicLoopKey, 0);
    int mute          = EchoInt(kMuteKey, 0);

    // الزر العائم 🎛️
    UIButton *fab = [UIButton buttonWithType:UIButtonTypeCustom];
    fab.frame = CGRectMake(20, 140, 52, 52);
    fab.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
    fab.layer.cornerRadius = 26;
    fab.layer.borderWidth = 1;
    fab.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
    [fab setTitle:@"🎛️" forState:UIControlStateNormal];
    fab.titleLabel.font = [UIFont systemFontOfSize:22];
    [fab addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragFab:)];
    [fab addGestureRecognizer:pan];
    [self.view addSubview:fab];
    self.fab = fab;

    // اللوحة الرئيسية 📱 (Creative EAX Console Style)
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kPanelW, kPanelH)];
    panel.backgroundColor = [UIColor colorWithRed:0.12 green:0.14 blue:0.18 alpha:0.96];
    panel.layer.cornerRadius = 16;
    panel.layer.borderWidth = 1.2;
    panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.2].CGColor;
    panel.hidden = YES;
    [self.view addSubview:panel];
    self.panel = panel;

    // زر إغلاق (✕)
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(kPanelW - 38, 12, 26, 26);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor colorWithWhite:1 alpha:0.8] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    closeBtn.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
    closeBtn.layer.cornerRadius = 13;
    [closeBtn addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:closeBtn];

    // التبويبات
    UISegmentedControl *tabs = [[UISegmentedControl alloc] initWithItems:@[@"EAX صدى", @"النبرة", @"المضخّم", @"🎵 أغاني"]];
    tabs.frame = CGRectMake(16, 12, kPanelW - 60, 34);
    tabs.selectedSegmentIndex = 0;
    tabs.selectedSegmentTintColor = [UIColor colorWithWhite:1 alpha:0.28];
    NSDictionary *white = @{ NSForegroundColorAttributeName: UIColor.whiteColor };
    [tabs setTitleTextAttributes:white forState:UIControlStateNormal];
    [tabs setTitleTextAttributes:white forState:UIControlStateSelected];
    [tabs addTarget:self action:@selector(tabChanged:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:tabs];
    self.tabs = tabs;

    CGRect cf = CGRectMake(0, kTabTop, kPanelW, kPanelH - kTabTop);
    UIView *tabEcho = [[UIView alloc] initWithFrame:cf];
    UIView *tabPitch = [[UIView alloc] initWithFrame:cf];
    UIView *tabAmp = [[UIView alloc] initWithFrame:cf];
    UIView *tabMusic = [[UIView alloc] initWithFrame:cf];
    self.tabViews = @[tabEcho, tabPitch, tabAmp, tabMusic];
    for (UIView *v in self.tabViews) { [panel addSubview:v]; v.hidden = (v != tabEcho); }

    CGFloat w = kPanelW - 32;

    // ================= تبويب الصدى (Creative EAX Console) =================
    UILabel *lblSwitch = [self makeLabelAt:CGRectMake(16, 10, w - 60, 28) size:14 bold:YES alpha:1];
    lblSwitch.textAlignment = NSTextAlignmentLeft;
    lblSwitch.text = @"Enable Audio Effects";
    [tabEcho addSubview:lblSwitch];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(w - 16, 8, 51, 31)];
    sw.on = (enableEffects != 0);
    [sw addTarget:self action:@selector(effectsToggled:) forControlEvents:UIControlEventValueChanged];
    [tabEcho addSubview:sw];
    self.effectsSwitch = sw;

    UILabel *lblPreset = [self makeLabelAt:CGRectMake(16, 52, w, 20) size:13 bold:YES alpha:0.8];
    lblPreset.textAlignment = NSTextAlignmentLeft;
    lblPreset.text = @"Active Environment (Preset)";
    [tabEcho addSubview:lblPreset];

    UISegmentedControl *presetSeg = [[UISegmentedControl alloc] initWithItems:@[@"Haunted Cavern", @"Cathedral", @"Concert Hall"]];
    presetSeg.frame = CGRectMake(16, 78, w, 32];
    presetSeg.selectedSegmentIndex = (preset >= 0 && preset <= 2) ? preset : 0;
    presetSeg.selectedSegmentTintColor = [UIColor systemIndigoColor];
    [presetSeg setTitleTextAttributes:white forState:UIControlStateNormal];
    [presetSeg setTitleTextAttributes:white forState:UIControlStateSelected];
    [presetSeg addTarget:self action:@selector(presetChanged:) forControlEvents:UIControlEventValueChanged];
    [tabEcho addSubview:presetSeg];
    self.presetSeg = presetSeg;

    self.amountLabel = [self makeLabelAt:CGRectMake(16, 130, w, 24) size:14 bold:YES alpha:1];
    self.amountLabel.textAlignment = NSTextAlignmentLeft;
    [tabEcho addSubview:self.amountLabel];

    UISlider *amountSlider = [self makeSliderAt:CGRectMake(16, 160, w, 30) min:0 max:100 value:amount action:@selector(amountChanged:)];
    [tabEcho addSubview:amountSlider];
    self.amountSlider = amountSlider;

    UILabel *eaxHint = [self makeLabelAt:CGRectMake(16, 210, w, 70) size:12 bold:NO alpha:0.55];
    eaxHint.text = @"مطابق لبرنامج Creative EAX Console. اختر بيئة 'Haunted Cavern' للصدى المرعب والعميق، وتحكم بشدة التأثير بدقة.";
    [tabEcho addSubview:eaxHint];

    // ================= تبويب النبرة =================
    self.pitchLabel = [self makeLabelAt:CGRectMake(16, 10, w, 26) size:16 bold:YES alpha:1];
    [tabPitch addSubview:self.pitchLabel];
    self.pitchSlider = [self makeSliderAt:CGRectMake(16, 42, w, 30) min:-12 max:12 value:pitch action:@selector(pitchChanged:)];
    [tabPitch addSubview:self.pitchSlider];

    NSArray *names = @[@"عادي", @"بنت", @"رجل", @"وحش", @"روبوت", @"🎲 عشوائي"];
    CGFloat pbw = (w - 16) / 3.0;
    for (NSInteger i = 0; i < 6; i++) {
        NSInteger col = i % 3, row = i / 3;
        CGRect f = CGRectMake(16 + col * (pbw + 8), 90 + row * 44, pbw, 36);
        [tabPitch addSubview:[self makeButton:names[i] frame:f tag:i action:@selector(presetTapped:)]];
    }

    // ================= تبويب المضخّم =================
    self.gainLabel = [self makeLabelAt:CGRectMake(16, 10, w, 26) size:16 bold:YES alpha:1];
    [tabAmp addSubview:self.gainLabel];
    self.gainSlider = [self makeSliderAt:CGRectMake(16, 42, w, 30) min:100 max:800 value:gain action:@selector(gainChanged:)];
    [tabAmp addSubview:self.gainSlider];

    NSArray *quickNames = @[@"عادي", @"×2", @"×3", @"×5", @"×8"];
    NSArray *quickTags  = @[@100, @200, @300, @500, @800];
    CGFloat qbw = (w - 8 * 4) / 5.0;
    for (NSInteger i = 0; i < 5; i++) {
        CGRect f = CGRectMake(16 + i * (qbw + 8), 86, qbw, 32);
        [tabAmp addSubview:[self makeButton:quickNames[i] frame:f tag:[quickTags[i] integerValue] action:@selector(gainQuick:)]];
    }

    UILabel *meterLabel = [self makeLabelAt:CGRectMake(16, 134, w, 18) size:13 bold:NO alpha:0.7];
    meterLabel.textAlignment = NSTextAlignmentLeft;
    meterLabel.text = @"مستوى المايك (Peak Meter)";
    [tabAmp addSubview:meterLabel];

    UIProgressView *meter = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    meter.frame = CGRectMake(16, 160, w, 8);
    meter.trackTintColor = [UIColor colorWithWhite:1 alpha:0.15];
    meter.progressTintColor = [UIColor systemGreenColor];
    [tabAmp addSubview:meter];
    self.meter = meter;

    // ================= تبويب الأغاني =================
    self.songLabel = [self makeLabelAt:CGRectMake(16, 10, w, 34) size:13 bold:YES alpha:1];
    self.songLabel.text = @"ما فيه أغنية. اختر ملف صوتي من ملفات الجهاز";
    [tabMusic addSubview:self.songLabel];

    [tabMusic addSubview:[self makeButton:@"📂 اختر أغنية" frame:CGRectMake(16, 52, w, 36) tag:0 action:@selector(chooseSong)]];

    UISlider *seek = [self makeSliderAt:CGRectMake(16, 100, w, 28) min:0 max:1 value:0 action:@selector(seekChanged:)];
    [seek addTarget:self action:@selector(seekBegan:) forControlEvents:UIControlEventTouchDown];
    [seek addTarget:self action:@selector(seekEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [tabMusic addSubview:seek];
    self.seekSlider = seek;

    self.timeLabel = [self makeLabelAt:CGRectMake(16, 132, w, 18) size:12 bold:NO alpha:0.7];
    self.timeLabel.text = @"0:00 / 0:00";
    [tabMusic addSubview:self.timeLabel];

    CGFloat hb = (w - 8) / 2.0;
    self.playBtn = [self makeButton:@"▶︎ تشغيل" frame:CGRectMake(16, 160, hb, 36) tag:0 action:@selector(playTapped)];
    [tabMusic addSubview:self.playBtn];
    [tabMusic addSubview:[self makeButton:@"⏹ إيقاف" frame:CGRectMake(16 + hb + 8, 160, hb, 36) tag:0 action:@selector(stopTapped)]];

    self.volLabel = [self makeLabelAt:CGRectMake(16, 208, w, 24) size:14 bold:YES alpha:1];
    self.volLabel.textAlignment = NSTextAlignmentLeft;
    [tabMusic addSubview:self.volLabel];
    self.volSlider = [self makeSliderAt:CGRectMake(16, 234, w, 30) min:0 max:200 value:mvol action:@selector(volChanged:)];
    [tabMusic addSubview:self.volSlider];

    // تطبيق القيم الأولية
    [self updateAmountLabel:amount];
    DiscordEcho_SetEnableEffects(enableEffects);
    DiscordEcho_SetEffectsAmount(amount);
    DiscordEcho_SetPreset(preset);
    [self updatePitchLabel];
    [self updateGainLabel:gain];
    [self updateVolLabel:mvol];
    DiscordEcho_SetGain(gain);
    DiscordEcho_SetPitch(pitch);
    DiscordEcho_SetRobot(self.robot ? 1 : 0);
    DiscordEcho_MusicSetVolume(mvol);
    DiscordEcho_MusicSetLoop(mloop);
    DiscordEcho_SetVoiceMute(mute);
}

- (void)updateAmountLabel:(int)v {
    self.amountLabel.text = [NSString stringWithFormat:@"Effects Amount : %d", v];
}
- (void)updatePitchLabel {
    int st = (int)lroundf(self.pitchSlider.value);
    NSString *t = (st == 0) ? @"النبرة: عادية" : [NSString stringWithFormat:@"النبرة: %+d نغمة", st];
    if (self.robot) t = [t stringByAppendingString:@"  ·  🤖 روبوت"];
    self.pitchLabel.text = t;
}
- (void)updateGainLabel:(int)v {
    self.gainLabel.text = [NSString stringWithFormat:@"تضخيم الصوت: %d%%", v];
}
- (void)updateVolLabel:(int)v {
    self.volLabel.text = [NSString stringWithFormat:@"مستوى الأغنية: %d%%", v];
}

- (void)tabChanged:(UISegmentedControl *)sender {
    for (NSUInteger i = 0; i < self.tabViews.count; i++)
        self.tabViews[i].hidden = ((NSInteger)i != sender.selectedSegmentIndex);
}

- (void)saveInt:(int)v key:(NSString *)k {
    [[NSUserDefaults standardUserDefaults] setInteger:v forKey:k];
}

// أزرار وتحكم الصدى
- (void)effectsToggled:(UISwitch *)s {
    DiscordEcho_SetEnableEffects(s.on ? 1 : 0);
    [self saveInt:s.on ? 1 : 0 key:kEffectsKey];
}
- (void)presetChanged:(UISegmentedControl *)s {
    DiscordEcho_SetPreset((int)s.selectedSegmentIndex);
    [self saveInt:(int)s.selectedSegmentIndex key:kPresetKey];
}
- (void)amountChanged:(UISlider *)s {
    int v = (int)lroundf(s.value);
    DiscordEcho_SetEffectsAmount(v);
    [self saveInt:v key:kAmountKey];
    [self updateAmountLabel:v];
}

// النبرة والمضخم
- (void)applyPitch:(int)st robot:(BOOL)robot {
    if (st < -12) st = -12;
    if (st > 12) st = 12;
    self.pitchSlider.value = st;
    self.robot = robot;
    DiscordEcho_SetPitch(st);
    DiscordEcho_SetRobot(robot ? 1 : 0);
    [self saveInt:st key:kPitchKey];
    [self saveInt:robot ? 1 : 0 key:kRobotKey];
    [self updatePitchLabel];
}
- (void)pitchChanged:(UISlider *)s { [self applyPitch:(int)lroundf(s.value) robot:self.robot]; }
- (void)presetTapped:(UIButton *)b {
    switch (b.tag) {
        case 0: [self applyPitch:0  robot:NO];  break;
        case 1: [self applyPitch:5  robot:NO];  break;
        case 2: [self applyPitch:-4 robot:NO];  break;
        case 3: [self applyPitch:-9 robot:NO];  break;
        case 4: [self applyPitch:0  robot:YES]; break;
        default: {
            int st = (int)arc4random_uniform(21) - 10;
            [self applyPitch:st robot:(arc4random_uniform(4) == 0)];
        }
    }
}

- (void)gainChanged:(UISlider *)s {
    int v = (int)lroundf(s.value);
    DiscordEcho_SetGain(v); [self saveInt:v key:kGainKey]; [self updateGainLabel:v];
}
- (void)gainQuick:(UIButton *)b {
    self.gainSlider.value = (float)b.tag;
    [self gainChanged:self.gainSlider];
}

// الأغاني
- (void)chooseSong {
    UIDocumentPickerViewController *p =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeAudio] asCopy:YES];
    p.delegate = self;
    p.allowsMultipleSelection = NO;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (url) [self loadSongAtURL:url];
}

- (void)loadSongAtURL:(NSURL *)url {
    NSString *name = url.lastPathComponent;
    DiscordEcho_MusicPlay(0);
    self.songLabel.text = [NSString stringWithFormat:@"⏳ جاري التحميل: %@", name];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        size_t count = 0;
        BOOL truncated = NO;
        float *buf = EchoDecodeFile(url, &count, &truncated);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!buf) {
                self.songLabel.text = @"❌ تعذر قراءة الملف. جرّب mp3 أو wav";
                return;
            }
            DiscordEcho_MusicLoad(buf, count);
            NSString *t = [NSString stringWithFormat:@"🎵 %@", name];
            if (truncated) t = [t stringByAppendingString:@" (أول 8 دقائق)"];
            self.songLabel.text = t;
            [self refreshMusicUI];
        });
    });
}

- (void)refreshMusicUI {
    float dur = DiscordEcho_MusicDuration();
    float prog = DiscordEcho_MusicProgress();
    if (!self.seeking) self.seekSlider.value = prog;
    self.timeLabel.text = [NSString stringWithFormat:@"%@ / %@", EchoTime(prog * dur), EchoTime(dur)];
    [self.playBtn setTitle:(DiscordEcho_MusicIsPlaying() ? @"⏸ إيقاف مؤقت" : @"▶︎ تشغيل") forState:UIControlStateNormal];
}

- (void)playTapped {
    DiscordEcho_MusicPlay(DiscordEcho_MusicIsPlaying() ? 0 : 1);
    [self refreshMusicUI];
}
- (void)stopTapped {
    DiscordEcho_MusicStop();
    self.seekSlider.value = 0;
    [self refreshMusicUI];
}
- (void)seekBegan:(UISlider *)s { self.seeking = YES; }
- (void)seekChanged:(UISlider *)s {
    float dur = DiscordEcho_MusicDuration();
    self.timeLabel.text = [NSString stringWithFormat:@"%@ / %@", EchoTime(s.value * dur), EchoTime(dur)];
}
- (void)seekEnded:(UISlider *)s {
    DiscordEcho_MusicSeek(s.value);
    self.seeking = NO;
}
- (void)volChanged:(UISlider *)s {
    int v = (int)lroundf(s.value);
    DiscordEcho_MusicSetVolume(v); [self saveInt:v key:kMusicVolKey]; [self updateVolLabel:v];
}

#pragma mark - المؤقت والموقع

- (void)startTimer {
    if (self.timer) return;
    __weak EchoController *ws = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) {
        EchoController *s = ws;
        if (!s || s.panel.hidden) return;
        NSInteger tab = s.tabs.selectedSegmentIndex;
        if (tab == 2) {
            float pk = DiscordEcho_GetPeak();
            if (pk > 1.0f) pk = 1.0f;
            s.meter.progress = pk;
            s.meter.progressTintColor = (pk > 0.98f) ? [UIColor systemRedColor]
                                      : (pk > 0.8f)  ? [UIColor systemOrangeColor]
                                                     : [UIColor systemGreenColor];
        } else if (tab == 3) {
            [s refreshMusicUI];
        }
    }];
}

- (void)stopTimer {
    [self.timer invalidate];
    self.timer = nil;
}

- (void)togglePanel {
    self.panel.hidden = !self.panel.hidden;
    if (self.panel.hidden) {
        [self stopTimer];
    } else {
        [self positionPanel];
        [self startTimer];
    }
}

- (void)positionPanel {
    CGRect b = self.view.bounds;
    CGFloat w = kPanelW, h = kPanelH;
    CGFloat x = CGRectGetMidX(self.fab.frame) - w / 2;
    x = MAX(10, MIN(x, b.size.width - w - 10));
    CGFloat y = CGRectGetMaxY(self.fab.frame) + 10;
    if (y + h > b.size.height - 10) y = CGRectGetMinY(self.fab.frame) - h - 10;
    y = MAX(10, y);
    self.panel.frame = CGRectMake(x, y, w, h);
}

- (void)dragFab:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.view];
    self.fab.center = CGPointMake(self.fab.center.x + t.x, self.fab.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.view];
    [self clampFab];
    if (!self.panel.hidden) [self positionPanel];
}

- (void)clampFab {
    CGRect b = self.view.bounds;
    UIEdgeInsets s = self.view.safeAreaInsets;
    CGFloat r = 26;
    CGPoint c = self.fab.center;
    c.x = MAX(r + s.left, MIN(c.x, b.size.width - r - s.right));
    c.y = MAX(r + s.top,  MIN(c.y, b.size.height - r - s.bottom));
    self.fab.center = c;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self clampFab];
    if (!self.panel.hidden) [self positionPanel];
}

@end

#pragma mark - تشغيل النافذة فوق ديسكورد

static EchoWindow *gWin;

static void echo_setup_window(void) {
    if (gWin) return;
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class] &&
            s.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)s;
            break;
        }
    }
    if (!scene) return;
    gWin = [[EchoWindow alloc] initWithWindowScene:scene];
    gWin.windowLevel = UIWindowLevelAlert + 100;
    gWin.backgroundColor = UIColor.clearColor;
    gWin.rootViewController = [EchoController new];
    gWin.hidden = NO;
}

__attribute__((constructor))
static void echo_ui_init(void) {
    DiscordEcho_SetEnableEffects(EchoInt(kEffectsKey, 1));
    DiscordEcho_SetEffectsAmount(EchoInt(kAmountKey, 50));
    DiscordEcho_SetPreset(EchoInt(kPresetKey, 0));
    DiscordEcho_SetGain(EchoInt(kGainKey, 100));
    DiscordEcho_SetPitch(EchoInt(kPitchKey, 0));
    DiscordEcho_SetRobot(EchoInt(kRobotKey, 0));
    DiscordEcho_MusicSetVolume(EchoInt(kMusicVolKey, 100));
    DiscordEcho_MusicSetLoop(EchoInt(kMusicLoopKey, 0));
    DiscordEcho_SetVoiceMute(EchoInt(kMuteKey, 0));

    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *n) { echo_setup_window(); }];
}
