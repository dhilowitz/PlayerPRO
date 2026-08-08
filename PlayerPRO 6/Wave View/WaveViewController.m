//
//  WaveViewController.m
//  PPMacho
//
//  Created by C.W. Betts on 7/26/14.
//
//

#import "WaveViewController.h"
#import "PlayerPRO_6-Swift.h"
#import <PlayerPROKit/PlayerPROKit.h>

static void *kWaveMusicContext = &kWaveMusicContext;

@interface WaveViewController ()
@property (nonatomic, strong) NSScrollView *gridScrollView;
@property (nonatomic, strong) PPWaveGridView *gridView;
@property (nonatomic, weak) PPDocument *observedDocument;
@property (nonatomic, strong) NSSegmentedControl *modeControl;
@property (nonatomic, strong) NSPopUpButton *ySizePopup;
@end

@implementation WaveViewController

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Initialization code here.
    }
    return self;
}

- (void)dealloc
{
	[_observedDocument removeObserver:self forKeyPath:@"theMusic" context:kWaveMusicContext];
	[_observedDocument removeObserver:self forKeyPath:@"currentPatternID" context:kWaveMusicContext];
}

- (void)viewDidLoad
{
	[super viewDidLoad];

	// Same reasoning as ClassicalViewController: the Wave tab's view arrives
	// from the nib empty, so the grid, its scroller and the control strip
	// are all built here rather than in Interface Builder.
	self.gridView = [[PPWaveGridView alloc] initWithFrame:NSZeroRect];

	NSRect bounds = self.view.bounds;
	const CGFloat stripHeight = 30;

	NSScrollView *scroller = [[NSScrollView alloc] initWithFrame:
							  NSMakeRect(0, 0, bounds.size.width, bounds.size.height - stripHeight)];
	scroller.hasVerticalScroller = YES;
	scroller.hasHorizontalScroller = YES;
	scroller.autohidesScrollers = NO;
	scroller.borderType = NSBezelBorder;
	scroller.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	scroller.documentView = self.gridView;
	[self.view addSubview:scroller];
	self.gridScrollView = scroller;

	[self buildControlStripAbove:scroller inBounds:bounds height:stripHeight];

	__weak typeof(self) weakSelf = self;
	self.gridView.positionSelected = ^(NSInteger row, NSInteger track) {
		[weakSelf.currentDocument.mainViewController selectDigitalPosition:row track:track];
	};

	PPDocument *doc = [self resolvedDocument];
	if (doc) {
		[doc addObserver:self
			  forKeyPath:@"theMusic"
				 options:NSKeyValueObservingOptionInitial
				 context:kWaveMusicContext];
		[doc addObserver:self
			  forKeyPath:@"currentPatternID"
				 options:0
				 context:kWaveMusicContext];
		self.observedDocument = doc;
	}
}

#pragma mark - Control strip

// Mode buttons (Play/Zoom/Note, matching the original's three dialog
// buttons, cycled by Tab the same way), a Y-zoom popup (the original's five
// fixed row-height choices), and a reminder of the mute/solo gesture, which
// has no visible control in the original either -- it's gutter-click-only
// there too.
- (void)buildControlStripAbove:(NSView *)scroller inBounds:(NSRect)bounds height:(CGFloat)stripHeight
{
	NSView *strip = [[NSView alloc] initWithFrame:
					 NSMakeRect(0, bounds.size.height - stripHeight, bounds.size.width, stripHeight)];
	strip.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;

	CGFloat x = 6;

	NSSegmentedControl *modeControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(x, 4, 180, 22)];
	modeControl.segmentCount = 3;
	[modeControl setLabel:NSLocalizedString(@"Play", @"wave editor mode") forSegment:0];
	[modeControl setLabel:NSLocalizedString(@"Zoom", @"wave editor mode") forSegment:1];
	[modeControl setLabel:NSLocalizedString(@"Note", @"wave editor mode") forSegment:2];
	modeControl.segmentStyle = NSSegmentStyleRounded;
	modeControl.selectedSegment = 0;
	modeControl.target = self;
	modeControl.action = @selector(modeChanged:);
	[strip addSubview:modeControl];
	self.modeControl = modeControl;
	x += NSWidth(modeControl.frame) + 14;

	x = [self addLabel:NSLocalizedString(@"Zoom Y:", @"wave editor y-zoom label") atX:x toStrip:strip];

	NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x, 4, 70, 22) pullsDown:NO];
	[popup addItemsWithTitles:@[@"16", @"32", @"64", @"128", @"256"]];
	[popup selectItemWithTitle:@"32"];
	popup.target = self;
	popup.action = @selector(ySizeChanged:);
	[strip addSubview:popup];
	self.ySizePopup = popup;
	x += NSWidth(popup.frame) + 14;

	x = [self addLabel:NSLocalizedString(@"⌘-click: mute · ⌥-click: solo", @"wave editor mute/solo hint")
					atX:x toStrip:strip];

	[self.view addSubview:strip];
}

- (CGFloat)addLabel:(NSString *)text atX:(CGFloat)x toStrip:(NSView *)strip
{
	NSTextField *label = [NSTextField labelWithString:text];
	[label sizeToFit];
	label.frame = NSMakeRect(x, 7, NSWidth(label.frame), 17);
	[strip addSubview:label];
	return x + NSWidth(label.frame) + 4;
}

- (IBAction)modeChanged:(id)sender
{
	self.gridView.mode = (WaveGridMode)self.modeControl.selectedSegment;
	[self.view.window makeFirstResponder:self.gridView];
}

- (IBAction)ySizeChanged:(id)sender
{
	NSString *title = self.ySizePopup.selectedItem.title;
	[self.gridView changeYSize:title.doubleValue];
	[self.view.window makeFirstResponder:self.gridView];
}

// Same nib quirk ClassicalViewController works around: currentDocument is
// wired to File's Owner, which for PPDocument.xib is the
// DocumentWindowController rather than the document itself.
- (PPDocument *)resolvedDocument
{
	id candidate = self.currentDocument;
	if ([candidate isKindOfClass:[PPDocument class]]) {
		return candidate;
	}
	if ([candidate respondsToSelector:@selector(currentDocument)]) {
		id inner = [candidate currentDocument];
		if ([inner isKindOfClass:[PPDocument class]]) {
			return inner;
		}
	}
	if ([candidate respondsToSelector:@selector(document)]) {
		id inner = [candidate document];
		if ([inner isKindOfClass:[PPDocument class]]) {
			return inner;
		}
	}
	return nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
						change:(NSDictionary *)change context:(void *)context
{
	if (context == kWaveMusicContext) {
		[self reloadFromDocument];
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

- (void)reloadFromDocument
{
	PPDocument *doc = [self resolvedDocument];
	PPMusicObject *music = doc.theMusic;
	if (!music || music.patterns.count == 0) {
		self.gridView.pattern = nil;
		self.gridView.music = nil;
		return;
	}

	NSInteger patternID = doc.currentPatternID;
	if (patternID < 0 || patternID >= (NSInteger)music.patterns.count) {
		patternID = 0;
	}

	self.gridView.trackCount = MAX(1, (NSInteger)music.totalTracks);
	self.gridView.music = music;
	self.gridView.pattern = music.patterns[patternID];
	self.gridView.driver = doc.theDriver;
}

@end
