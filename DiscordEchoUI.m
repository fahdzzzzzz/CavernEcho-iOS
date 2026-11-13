#pragma mark - بحث الأغاني (4 مصادر تشمل اليوتيوب)

// 0 = iTunes، 1 = Internet Archive، 2 = Audius، 3 = YouTube (بحث واستخراج صوت)
@interface EchoSearchController : UIViewController <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, copy) void (^onPick)(NSURL *fileURL, NSString *name);
@property (nonatomic, strong) UISearchBar *bar;
@property (nonatomic, strong) UISegmentedControl *src;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) UIButton *closeBtn;
@property (nonatomic, strong) NSArray<NSDictionary *> *items;
@property (nonatomic, strong) NSURLSessionTask *task;
@end

@implementation EchoSearchController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];

    self.closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.closeBtn setTitle:@"✕ إغلاق" forState:UIControlStateNormal];
    [self.closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.closeBtn];

    self.src = [[UISegmentedControl alloc] initWithItems:@[@"🎵 مشاهير", @"🆓 Archive", @"Audius", @"📺 يوتيوب"]];
    self.src.selectedSegmentIndex = 3; // افتصادياً نخليه على اليوتيوب لطلباتك
    self.src.selectedSegmentTintColor = [UIColor colorWithWhite:1 alpha:0.28];
    NSDictionary *white = @{ NSForegroundColorAttributeName: UIColor.whiteColor,
                             NSFontAttributeName: [UIFont boldSystemFontOfSize:11] };
    [self.src setTitleTextAttributes:white forState:UIControlStateNormal];
    [self.src setTitleTextAttributes:white forState:UIControlStateSelected];
    [self.src addTarget:self action:@selector(sourceChanged) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.src];

    self.bar = [[UISearchBar alloc] init];
    self.bar.placeholder = @"🔍 ابحث باسم الأغنية أو الصق رابط يوتيوب هنا";
    self.bar.delegate = self;
    self.bar.searchBarStyle = UISearchBarStyleMinimal;
    self.bar.returnKeyType = UIReturnKeySearch;
    [self.view addSubview:self.bar];

    self.status = [[UILabel alloc] init];
    self.status.textAlignment = NSTextAlignmentCenter;
    self.status.font = [UIFont systemFontOfSize:12];
    self.status.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    self.status.numberOfLines = 2;
    [self.view addSubview:self.status];
    [self sourceChanged];

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.backgroundColor = UIColor.clearColor;
    self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.table];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    self.closeBtn.frame = CGRectMake(b.size.width - 96, 10, 84, 34);
    self.src.frame = CGRectMake(16, 48, b.size.width - 32, 32);
    self.bar.frame = CGRectMake(8, 84, b.size.width - 16, 50);
    self.status.frame = CGRectMake(16, 136, b.size.width - 32, 38);
    self.table.frame = CGRectMake(0, 178, b.size.width, b.size.height - 178);
}

- (void)closeTapped {
    [self.task cancel];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)sourceChanged {
    [self.task cancel];
    self.items = @[];
    [self.table reloadData];
    switch (self.src.selectedSegmentIndex) {
        case 0: self.status.text = @"أغاني مشهورة من iTunes (مقطع 30 ثانية)"; break;
        case 1: self.status.text = @"أغاني كاملة من Internet Archive"; break;
        case 2: self.status.text = @"أغاني كاملة من منصة Audius"; break;
        case 3: self.status.text = @"📺 بوت يوتيوب: ابحث بأي اسم أو الصق رابط فيديو يوتيوب مباشرة ليشمله الصدى ويسمعه معك الجميع!"; break;
        default: break;
    }
}

static NSString *EchoStr(id v) { return [v isKindOfClass:NSString.class] ? v : @""; }
static float EchoNum(id v) { return [v isKindOfClass:NSNumber.class] ? [v floatValue] : 0.0f; }

- (void)finishSearch:(NSArray *)out failed:(BOOL)failed code:(NSInteger)code {
    self.items = out;
    [self.table reloadData];
    if (failed) self.status.text = @"❌ فشل الاتصال بالبحث. تأكد من الإنترنت";
    else if (out.count == 0) self.status.text = @"ما لقيت نتائج، جرّب كلمة بحث أخرى أو رابط يوتيوب مباشر";
    else self.status.text = [NSString stringWithFormat:@"%lu نتيجة جاهزة للتشغيل في الروم", (unsigned long)out.count];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)bar {
    [bar resignFirstResponder];
    NSString *q = [bar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (q.length == 0) return;
    [self.task cancel];
    self.status.text = @"⏳ جاري البحث أو جلب الصوت…";

    NSInteger source = self.src.selectedSegmentIndex;
    
    // إذا كان المصدر يوتيوب (3)
    if (source == 3) {
        // التحقق هل هو رابط يوتيوب مباشر
        NSString *videoId = nil;
        if ([q containsString:@"youtu.be/"]) {
            NSArray *parts = [q componentsSeparatedByString:@"youtu.be/"];
            if (parts.count > 1) videoId = [[parts[1] componentsSeparatedByString:@"?"] firstObject];
        } else if ([q containsString:@"watch?v="]) {
            NSArray *parts = [q componentsSeparatedByString:@"watch?v="];
            if (parts.count > 1) videoId = [[parts[1] componentsSeparatedByString:@"&"] firstObject];
        }
        
        NSURLComponents *c = nil;
        if (videoId && videoId.length > 0) {
            // جلب الرابط المباشر عبر API عام لـ Piped/Invidious
            c = [NSURLComponents componentsWithString:[NSString stringWithFormat:@"https://pipedapi.kavin.rocks/streams/%@", videoId]];
        } else {
            // بحث في اليوتيوب
            c = [NSURLComponents componentsWithString:@"https://pipedapi.kavin.rocks/search"];
            c.queryItems = @[ [NSURLQueryItem queryItemWithName:@"q" value:q] ];
        }

        __weak EchoSearchController *ws = self;
        NSURLSessionDataTask *t = [NSURLSession.sharedSession dataTaskWithURL:c.URL
            completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
            if (e && e.code == NSURLErrorCancelled) return;
            NSMutableArray *out = [NSMutableArray array];
            id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
            
            if (videoId && [j isKindOfClass:NSDictionary.class]) {
                // استخراج رابط الصوت المباشر للفيديو الملصق
                NSArray *audioStreams = j[@"audioStreams"];
                if ([audioStreams isKindOfClass:NSArray.class] && audioStreams.count > 0) {
                    NSDictionary *bestAudio = audioStreams.firstObject;
                    NSString *urlStr = EchoStr(bestAudio[@"url"]);
                    if (urlStr.length > 0) {
                        [out addObject:@{ @"title": EchoStr(j[@"title"]) ?: @"مقطع يوتيوب", @"artist": @"YouTube", @"url": urlStr, @"ext": @"m4a" }];
                    }
                }
            } else if ([j isKindOfClass:NSDictionary.class] && [j[@"items"] isKindOfClass:NSArray.class]) {
                // نتائج البحث
                for (id it in j[@"items"]) {
                    if (![it isKindOfClass:NSDictionary.class]) continue;
                    NSString *type = EchoStr(it[@"type"]);
                    if ([type isEqualToString:@"stream"] || type.length == 0) {
                        NSString *vId = EchoStr(it[@"url"]); // غالباً /watch?v=...
                        if ([vId containsString:@"v="]) {
                            vId = [[vId componentsSeparatedByString:@"v="] lastObject];
                        }
                        NSString *title = EchoStr(it[@"title"]);
                        NSString *uploader = EchoStr(it[@"uploaderName"]);
                        if (vId.length > 0 && title.length > 0) {
                            // رابط مؤقت لجلب الستريم عند الضغط
                            NSString *streamApi = [NSString stringWithFormat:@"https://pipedapi.kavin.rocks/streams/%@", vId];
                            [out addObject:@{ @"title": title, @"artist": uploader.length ? uploader : @"YouTube", @"api": streamApi, @"ext": @"m4a" }];
                        }
                    }
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                EchoSearchController *s = ws;
                if (!s) return;
                [s finishSearch:out failed:(e != nil) code:0];
            });
        }];
        self.task = t;
        [t resume];
        return;
    }

    // باقي المصادر (iTunes, Archive, Audius) كما هي...
    NSURLComponents *c = nil;
    if (source == 0) {
        c = [NSURLComponents componentsWithString:@"https://itunes.apple.com/search"];
        c.queryItems = @[ [NSURLQueryItem queryItemWithName:@"term" value:q],
                          [NSURLQueryItem queryItemWithName:@"media" value:@"music"],
                          [NSURLQueryItem queryItemWithName:@"entity" value:@"song"],
                          [NSURLQueryItem queryItemWithName:@"limit" value:@"30"] ];
    } else if (source == 1) {
        c = [NSURLComponents componentsWithString:@"https://archive.org/advancedsearch.php"];
        NSString *query = [NSString stringWithFormat:@"(title:(%@) OR creator:(%@)) AND mediatype:audio", q, q];
        c.queryItems = @[ [NSURLQueryItem queryItemWithName:@"q" value:query],
                          [NSURLQueryItem queryItemWithName:@"fl[]" value:@"identifier"],
                          [NSURLQueryItem queryItemWithName:@"fl[]" value:@"title"],
                          [NSURLQueryItem queryItemWithName:@"fl[]" value:@"creator"],
                          [NSURLQueryItem queryItemWithName:@"sort[]" value:@"downloads desc"],
                          [NSURLQueryItem queryItemWithName:@"rows" value:@"30"],
                          [NSURLQueryItem queryItemWithName:@"output" value:@"json"] ];
    } else {
        c = [NSURLComponents componentsWithString:@"https://api.audius.co/v1/tracks/search"];
        c.queryItems = @[ [NSURLQueryItem queryItemWithName:@"query" value:q],
                          [NSURLQueryItem queryItemWithName:@"limit" value:@"25"],
                          [NSURLQueryItem queryItemWithName:@"app_name" value:kEchoAppName] ];
    }

    __weak EchoSearchController *ws = self;
    NSURLSessionDataTask *t = [NSURLSession.sharedSession dataTaskWithURL:c.URL
        completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        if (e && e.code == NSURLErrorCancelled) return;
        NSInteger code = [r isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)r).statusCode : 0;
        NSMutableArray *out = [NSMutableArray array];
        BOOL ok = (d != nil && e == nil && code >= 200 && code < 300);
        id j = ok ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
        if ([j isKindOfClass:NSDictionary.class]) {
            NSDictionary *root = j;
            if (source == 0) {
                id arr = root[@"results"];
                if ([arr isKindOfClass:NSArray.class]) for (id it in (NSArray *)arr) {
                    if (![it isKindOfClass:NSDictionary.class]) continue;
                    NSString *prev = EchoStr(it[@"previewUrl"]);
                    if (prev.length == 0) continue;
                    [out addObject:@{ @"title": EchoStr(it[@"trackName"]), @"artist": EchoStr(it[@"artistName"]),
                                      @"dur": @(EchoNum(it[@"trackTimeMillis"]) / 1000.0f > 30 ? 30.0f : EchoNum(it[@"trackTimeMillis"]) / 1000.0f),
                                      @"url": prev, @"ext": @"m4a" }];
                }
            } else if (source == 1) {
                id resp = root[@"response"];
                id arr = [resp isKindOfClass:NSDictionary.class] ? ((NSDictionary *)resp)[@"docs"] : nil;
                if ([arr isKindOfClass:NSArray.class]) for (id it in (NSArray *)arr) {
                    if (![it isKindOfClass:NSDictionary.class]) continue;
                    NSString *ident = EchoStr(it[@"identifier"]);
                    if (ident.length == 0) continue;
                    id cr = it[@"creator"];
                    if ([cr isKindOfClass:NSArray.class]) cr = [(NSArray *)cr firstObject];
                    id ti = it[@"title"];
                    if ([ti isKindOfClass:NSArray.class]) ti = [(NSArray *)ti firstObject];
                    [out addObject:@{ @"title": EchoStr(ti).length ? EchoStr(ti) : ident, @"artist": EchoStr(cr),
                                      @"dur": @0, @"archive": ident }];
                }
            } else {
                id arr = root[@"data"];
                if ([arr isKindOfClass:NSArray.class]) for (id it in (NSArray *)arr) {
                    if (![it isKindOfClass:NSDictionary.class]) continue;
                    NSDictionary *tr = it;
                    NSString *tid = EchoStr(tr[@"id"]);
                    if (tid.length == 0 || EchoStr(tr[@"title"]).length == 0) continue;
                    id streamable = tr[@"is_streamable"];
                    if ([streamable isKindOfClass:NSNumber.class] && ![streamable boolValue]) continue;
                    if ([tr[@"stream_conditions"] isKindOfClass:NSDictionary.class]) continue;
                    id user = tr[@"user"];
                    NSString *artist = [user isKindOfClass:NSDictionary.class] ? EchoStr(user[@"name"]) : @"";
                    NSString *u = [NSString stringWithFormat:@"https://api.audius.co/v1/tracks/%@/stream?app_name=%@", tid, kEchoAppName];
                    [out addObject:@{ @"title": EchoStr(tr[@"title"]), @"artist": artist,
                                      @"dur": @(EchoNum(tr[@"duration"])), @"url": u, @"ext": @"mp3" }];
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            EchoSearchController *s = ws;
            if (!s) return;
            [s finishSearch:out failed:!ok code:code];
        });
    }];
    self.task = t;
    [t resume];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.items.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
        cell.backgroundColor = UIColor.clearColor;
        cell.textLabel.textColor = UIColor.whiteColor;
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    }
    NSDictionary *it = self.items[ip.row];
    cell.textLabel.text = it[@"title"];
    cell.detailTextLabel.text = it[@"artist"];
    return cell;
}

- (void)failDownload:(NSString *)msg {
    self.view.userInteractionEnabled = YES;
    self.status.text = msg;
}

- (void)downloadURL:(NSURL *)url ext:(NSString *)ext name:(NSString *)name {
    __weak EchoSearchController *ws = self;
    NSURLSessionDownloadTask *t = [NSURLSession.sharedSession downloadTaskWithURL:url
        completionHandler:^(NSURL *loc, NSURLResponse *resp, NSError *err) {
        if (err && err.code == NSURLErrorCancelled) return;
        NSInteger code = [resp isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
        NSURL *dest = nil;
        if (loc && !err && code >= 200 && code < 300) {
            NSString *fn = [NSString stringWithFormat:@"echo_%u.%@", arc4random(), ext];
            dest = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:fn]];
            [[NSFileManager defaultManager] removeItemAtURL:dest error:nil];
            if (![[NSFileManager defaultManager] moveItemAtURL:loc toURL:dest error:nil]) dest = nil;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            EchoSearchController *s = ws;
            if (!s) return;
            if (!dest) {
                [s failDownload:@"❌ فشل جلب الرابط. جرّب مقطع يوتيوب آخر"];
                return;
            }
            s.view.userInteractionEnabled = YES;
            void (^cb)(NSURL *, NSString *) = s.onPick;
            [s dismissViewControllerAnimated:YES completion:^{ if (cb) cb(dest, name); }];
        });
    }];
    self.task = t;
    [t resume];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *it = self.items[ip.row];
    NSString *name = [it[@"artist"] length] ? [NSString stringWithFormat:@"%@ — %@", it[@"title"], it[@"artist"]] : it[@"title"];
    
    // إذا كان العنصر من يوتيوب وعنده api لجلب الرابط المباشر للستريم
    NSString *api = it[@"api"];
    if (api) {
        self.status.text = @"⏳ جاري استخراج الصوت من اليوتيوب…";
        self.view.userInteractionEnabled = NO;
        __weak EchoSearchController *ws = self;
        NSURLSessionDataTask *t = [NSURLSession.sharedSession dataTaskWithURL:[NSURL URLWithString:api]
            completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
            if (e && e.code == NSURLErrorCancelled) return;
            id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
            NSString *streamUrl = nil;
            if ([j isKindOfClass:NSDictionary.class]) {
                NSArray *audioStreams = j[@"audioStreams"];
                if ([audioStreams isKindOfClass:NSArray.class] && audioStreams.count > 0) {
                    streamUrl = EchoStr(audioStreams.firstObject[@"url"]);
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                EchoSearchController *s = ws;
                if (!s) return;
                if (!streamUrl) { [s failDownload:@"❌ تعذر استخراج الصوت من هذا الفيديو"]; return; }
                [s downloadURL:[NSURL URLWithString:streamUrl] ext:@"m4a" name:name];
            });
        }];
        self.task = t;
        [t resume];
        return;
    }

    NSString *directUrl = it[@"url"];
    if (directUrl) {
        self.status.text = @"⏳ جاري تحميل الأغنية…";
        self.view.userInteractionEnabled = NO;
        [self downloadURL:[NSURL URLWithString:directUrl] ext:(it[@"ext"] ?: @"m4a") name:name];
        return;
    }
    
    // التعامل مع الأرشيف أو البقية...
    // (باقي كود الـ archive إذا وجد)
}
@end
