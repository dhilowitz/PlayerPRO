//
//  DigitalViewController.m
//  PPMacho
//
//  Created by C.W. Betts on 7/26/14.
//
//

#import "DigitalViewController.h"
#import "PlayerPRO_6-Swift.h"
#import <PlayerPROKit/PlayerPROKit.h>

static void *kClassicMusicContext = &kClassicMusicContext;

@interface DigitalViewController ()
@property (nonatomic, strong) NSScrollView *gridScrollView;
@property (nonatomic, strong) PPClassicGridView *gridView;
@property (nonatomic, weak) PPDocument *observedDocument;
@property (nonatomic, strong) NSPopUpButton *trackPopup;
@property (nonatomic, strong) NSPopUpButton *instrumentPopup;
@property (nonatomic, strong) NSSegmentedControl *modeControl;
@end

@implementation DigitalViewController

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
	[_observedDocument removeObserver:self forKeyPath:@"theMusic" context:kClassicMusicContext];
	[_observedDocument removeObserver:self forKeyPath:@"currentPatternID" context:kClassicMusicContext];
}

- (void)viewDidLoad
{
	[super viewDidLoad];

	// Same reasoning as ClassicalViewController/WaveViewController: the tab's
	// view arrives from the nib empty, so the grid, its scroller and the
	// control strip are all built here rather than in Interface Builder.
	self.gridView = [[PPClassicGridView alloc] initWithFrame:NSZeroRect];

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

	PPDocument *doc = [self resolvedDocument];
	if (doc) {
		[doc addObserver:self
			  forKeyPath:@"theMusic"
				 options:NSKeyValueObservingOptionInitial
				 context:kClassicMusicContext];
		[doc addObserver:self
			  forKeyPath:@"currentPatternID"
				 options:0
				 context:kClassicMusicContext];
		self.observedDocument = doc;
	}
}

#pragma mark - Control strip

// Track and Instrument filter popups (the original's dialog items 7/8) and
// a Play/Zoom mode control (items 14/15) -- the original's Info button
// (item 12, pattern name/length editor) has no equivalent dialog anywhere
// in this port yet, so it's left out rather than built against nothing;
// pattern name/length are directly editable via PPPatternObject already if
// that's added later.
- (void)buildControlStripAbove:(NSView *)scroller inBounds:(NSRect)bounds height:(CGFloat)stripHeight
{
	NSView *strip = [[NSView alloc] initWithFrame:
					 NSMakeRect(0, bounds.size.height - stripHeight, bounds.size.width, stripHeight)];
	strip.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;

	CGFloat x = 6;

	NSSegmentedControl *modeControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(x, 4, 120, 22)];
	modeControl.segmentCount = 2;
	[modeControl setLabel:NSLocalizedString(@"Play", @"classic editor mode") forSegment:0];
	[modeControl setLabel:NSLocalizedString(@"Zoom", @"classic editor mode") forSegment:1];
	modeControl.segmentStyle = NSSegmentStyleRounded;
	modeControl.selectedSegment = 0;
	modeControl.target = self;
	modeControl.action = @selector(modeChanged:);
	[strip addSubview:modeControl];
	self.modeControl = modeControl;
	x += NSWidth(modeControl.frame) + 14;

	x = [self addLabel:NSLocalizedString(@"Track:", @"classic editor track filter label") atX:x toStrip:strip];

	NSPopUpButton *trackPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x, 4, 90, 22) pullsDown:NO];
	trackPopup.target = self;
	trackPopup.action = @selector(trackChanged:);
	[strip addSubview:trackPopup];
	self.trackPopup = trackPopup;
	x += NSWidth(trackPopup.frame) + 14;

	x = [self addLabel:NSLocalizedString(@"Instrument:", @"classic editor instrument filter label") atX:x toStrip:strip];

	NSPopUpButton *instrumentPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x, 4, 160, 22) pullsDown:NO];
	instrumentPopup.target = self;
	instrumentPopup.action = @selector(instrumentChanged:);
	[strip addSubview:instrumentPopup];
	self.instrumentPopup = instrumentPopup;

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
	self.gridView.mode = (ClassicGridMode)self.modeControl.selectedSegment;
	[self.view.window makeFirstResponder:self.gridView];
}

- (IBAction)trackChanged:(id)sender
{
	self.gridView.selectedTrack = self.trackPopup.indexOfSelectedItem - 1;
	[self.view.window makeFirstResponder:self.gridView];
}

- (IBAction)instrumentChanged:(id)sender
{
	self.gridView.selectedInstrument = self.instrumentPopup.indexOfSelectedItem - 1;
	[self.view.window makeFirstResponder:self.gridView];
}

#pragma mark - Document binding

// Same nib quirk ClassicalViewController/WaveViewController work around:
// currentDocument is wired to File's Owner, which for PPDocument.xib is the
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
	if (context == kClassicMusicContext) {
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
		return;
	}

	NSInteger patternID = doc.currentPatternID;
	if (patternID < 0 || patternID >= (NSInteger)music.patterns.count) {
		patternID = 0;
	}

	self.gridView.trackCount = MAX(1, (NSInteger)music.totalTracks);
	self.gridView.pattern = music.patterns[patternID];
	self.gridView.driver = doc.theDriver;

	[self rebuildTrackPopup:(NSInteger)music.totalTracks];
	[self rebuildInstrumentPopup:music.instruments];
}

- (void)rebuildTrackPopup:(NSInteger)trackCount
{
	[self.trackPopup removeAllItems];
	[self.trackPopup addItemWithTitle:NSLocalizedString(@"All Channels", @"classic editor track filter")];
	for (NSInteger i = 0; i < trackCount; i++) {
		[self.trackPopup addItemWithTitle:[NSString stringWithFormat:@"%ld", (long)(i + 1)]];
	}
	[self.trackPopup selectItemAtIndex:0];
	self.gridView.selectedTrack = -1;
}

- (void)rebuildInstrumentPopup:(NSArray<PPInstrumentObject *> *)instruments
{
	[self.instrumentPopup removeAllItems];
	[self.instrumentPopup addItemWithTitle:NSLocalizedString(@"All Instruments", @"classic editor instrument filter")];
	for (PPInstrumentObject *ins in instruments) {
		NSString *name = ins.name.length > 0 ? ins.name : NSLocalizedString(@"Untitled", @"unnamed instrument");
		[self.instrumentPopup addItemWithTitle:[NSString stringWithFormat:@"%ld %@", (long)(ins.number + 1), name]];
	}
	[self.instrumentPopup selectItemAtIndex:0];
	self.gridView.selectedInstrument = -1;
}

@end
