//
//  ClassicalViewController.m
//  PPMacho
//
//  Created by C.W. Betts on 7/26/14.
//
//

#import "ClassicalViewController.h"
#import "PlayerPRO_6-Swift.h"
#import <PlayerPROKit/PlayerPROKit.h>
#import <objc/runtime.h>

static void *kMusicContext = &kMusicContext;

@interface ClassicalViewController ()
@property (nonatomic, strong) NSScrollView *gridScrollView;
@property (nonatomic, strong) PPPatternGridView *gridView;
@property (nonatomic, weak) PPDocument *observedDocument;
@property (nonatomic, strong) NSView *controlStrip;
@property (nonatomic, strong) NSButton *recordButton;
@property (nonatomic, strong) NSTextField *stepField;
@property (nonatomic, strong) NSTextField *instrumentField;
@property (nonatomic, strong) NSTextField *octaveField;
@end

@implementation ClassicalViewController

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
	[_observedDocument removeObserver:self forKeyPath:@"theMusic" context:kMusicContext];
	[_observedDocument removeObserver:self forKeyPath:@"currentPatternID" context:kMusicContext];
}

- (void)viewDidLoad
{
	[super viewDidLoad];

	// The Classic tab's view arrives from the nib empty, so build the grid, its
	// scroller and the control strip here rather than in Interface Builder.
	self.gridView = [[PPPatternGridView alloc] initWithFrame:NSZeroRect];

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

	// Route edits through the document: its undo manager drives the Edit menu,
	// and the change count is what makes the window dirty and prompts to save.
	__weak typeof(self) weakSelf = self;
	self.gridView.didEditPattern = ^{
		[[weakSelf resolvedDocument] updateChangeCount:NSChangeDone];
	};

	PPDocument *doc = [self resolvedDocument];
	if (doc) {
		[doc addObserver:self
			  forKeyPath:@"theMusic"
				 options:NSKeyValueObservingOptionInitial
				 context:kMusicContext];
		[doc addObserver:self
			  forKeyPath:@"currentPatternID"
				 options:0
				 context:kMusicContext];
		self.observedDocument = doc;
	}
}

#pragma mark - Control strip

// Mirrors the row the classic editor shows above its grid: a record toggle,
// the step, and the instrument stamped alongside typed notes. Built in code
// because the Classic tab's view comes from the nib empty.
- (void)buildControlStripAbove:(NSView *)scroller inBounds:(NSRect)bounds height:(CGFloat)stripHeight
{
	NSView *strip = [[NSView alloc] initWithFrame:
					 NSMakeRect(0, bounds.size.height - stripHeight, bounds.size.width, stripHeight)];
	strip.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;

	CGFloat x = 6;

	// Record. Without this the grid cannot be navigated without typing notes
	// into it, which is how it behaved when note entry first landed.
	NSButton *record = [NSButton checkboxWithTitle:NSLocalizedString(@"Record", @"record toggle")
											target:self action:@selector(toggleRecord:)];
	[record sizeToFit];
	record.frame = NSMakeRect(x, 5, NSWidth(record.frame), 20);
	record.state = self.gridView.recording ? NSControlStateValueOn : NSControlStateValueOff;
	[strip addSubview:record];
	self.recordButton = record;
	x += NSWidth(record.frame) + 14;

	x = [self addLabel:NSLocalizedString(@"Step:", @"step label") atX:x toStrip:strip];
	self.stepField = [self addNumberFieldAtX:&x toStrip:strip
									   value:self.gridView.step
										 min:1 max:16
									  action:@selector(stepChanged:)];
	x += 14;

	x = [self addLabel:NSLocalizedString(@"Ins:", @"instrument label") atX:x toStrip:strip];
	self.instrumentField = [self addNumberFieldAtX:&x toStrip:strip
											 value:self.gridView.defaultInstrument
											   min:0 max:255
											action:@selector(instrumentChanged:)];
	x += 14;

	x = [self addLabel:NSLocalizedString(@"Oct:", @"octave label") atX:x toStrip:strip];
	self.octaveField = [self addNumberFieldAtX:&x toStrip:strip
										 value:self.gridView.octaveOffset
										   min:-4 max:4
										action:@selector(octaveChanged:)];

	[self.view addSubview:strip];
	self.controlStrip = strip;
}

- (CGFloat)addLabel:(NSString *)text atX:(CGFloat)x toStrip:(NSView *)strip
{
	NSTextField *label = [NSTextField labelWithString:text];
	[label sizeToFit];
	label.frame = NSMakeRect(x, 7, NSWidth(label.frame), 17);
	[strip addSubview:label];
	return x + NSWidth(label.frame) + 4;
}

- (NSTextField *)addNumberFieldAtX:(CGFloat *)x toStrip:(NSView *)strip
							 value:(NSInteger)value min:(NSInteger)minV max:(NSInteger)maxV
							action:(SEL)action
{
	NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(*x, 5, 40, 21)];
	field.alignment = NSTextAlignmentRight;
	field.integerValue = value;
	field.target = self;
	field.action = action;
	[strip addSubview:field];

	NSStepper *stepper = [[NSStepper alloc] initWithFrame:NSMakeRect(*x + 42, 4, 15, 23)];
	stepper.minValue = minV;
	stepper.maxValue = maxV;
	stepper.increment = 1;
	stepper.valueWraps = NO;
	stepper.integerValue = value;
	stepper.target = self;
	stepper.action = action;
	[strip addSubview:stepper];

	// so the action can find its partner whichever half the user touched
	field.tag = stepper.hash;
	objc_setAssociatedObject(field, @selector(addNumberFieldAtX:toStrip:value:min:max:action:),
							 stepper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(stepper, @selector(addNumberFieldAtX:toStrip:value:min:max:action:),
							 field, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	*x += 62;
	return field;
}

/// Read the value from whichever control fired and sync its partner.
- (NSInteger)syncedValueFrom:(id)sender
{
	NSInteger value = [sender integerValue];
	id partner = objc_getAssociatedObject(sender, @selector(addNumberFieldAtX:toStrip:value:min:max:action:));
	if ([partner respondsToSelector:@selector(setIntegerValue:)]) {
		if ([partner isKindOfClass:[NSStepper class]]) {
			NSStepper *st = partner;
			value = MAX((NSInteger)st.minValue, MIN((NSInteger)st.maxValue, value));
		}
		[partner setIntegerValue:value];
	}
	if ([sender respondsToSelector:@selector(setIntegerValue:)]) {
		[sender setIntegerValue:value];
	}
	return value;
}

- (IBAction)toggleRecord:(id)sender
{
	self.gridView.recording = ([sender state] == NSControlStateValueOn);
	[self.view.window makeFirstResponder:self.gridView];
}

- (IBAction)stepChanged:(id)sender
{
	self.gridView.step = [self syncedValueFrom:sender];
	[self.view.window makeFirstResponder:self.gridView];
}

- (IBAction)instrumentChanged:(id)sender
{
	self.gridView.defaultInstrument = (uint8_t)[self syncedValueFrom:sender];
	[self.view.window makeFirstResponder:self.gridView];
}

- (IBAction)octaveChanged:(id)sender
{
	self.gridView.octaveOffset = [self syncedValueFrom:sender];
	[self.view.window makeFirstResponder:self.gridView];
}

// The nib wires our currentDocument outlet to File's Owner, which for
// PPDocument.xib is the DocumentWindowController rather than the document,
// even though the property is declared PPDocument*. Rather than rely on that,
// accept either and ask the window controller for the document when that is
// what we were handed.
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
	if (context == kMusicContext) {
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

	// currentPatternID (settable from the Pattern List window) replaces
	// what used to be a hardcoded 0 -- every editor in this port showed
	// only the first pattern, since nothing else set it to anything else.
	NSInteger patternID = doc.currentPatternID;
	if (patternID < 0 || patternID >= (NSInteger)music.patterns.count) {
		patternID = 0;
	}

	self.gridView.editUndoManager = doc.undoManager;
	self.gridView.trackCount = MAX(1, (NSInteger)music.totalTracks);
	self.gridView.pattern = music.patterns[patternID];
}

@end
