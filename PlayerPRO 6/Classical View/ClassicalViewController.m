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
@property (nonatomic, strong) NSButton *volumeCheckbox;
@property (nonatomic, strong) NSTextField *volumeField;
@property (nonatomic, strong) NSButton *effectCheckbox;
@property (nonatomic, strong) NSTextField *effectField;
@property (nonatomic, strong) NSButton *argumentCheckbox;
@property (nonatomic, strong) NSTextField *argumentField;
@property (nonatomic, strong) NSTextField *lengthField;
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
	x += 14;

	// Vol/FX/Arg: PPPatternGridView already has writesVolume/writesEffect/
	// writesArgument + defaultVolume/defaultEffect/defaultArgument
	// (stamped onto typed notes alongside Ins/Oct) -- nothing in this
	// controller ever gave them a UI, so they always stayed off.
	NSButton *volCheckbox; NSTextField *volField;
	x = [self addToggleFieldAtX:&x toStrip:strip
						   title:NSLocalizedString(@"Vol", @"volume stamp toggle")
						 enabled:self.gridView.writesVolume value:self.gridView.defaultVolume
					enableAction:@selector(volumeEnableChanged:) valueAction:@selector(volumeValueChanged:)
						checkbox:&volCheckbox field:&volField];
	self.volumeCheckbox = volCheckbox;
	self.volumeField = volField;
	x += 10;

	NSButton *fxCheckbox; NSTextField *fxField;
	x = [self addToggleFieldAtX:&x toStrip:strip
						   title:NSLocalizedString(@"FX", @"effect stamp toggle")
						 enabled:self.gridView.writesEffect value:self.gridView.defaultEffect
					enableAction:@selector(effectEnableChanged:) valueAction:@selector(effectValueChanged:)
						checkbox:&fxCheckbox field:&fxField];
	self.effectCheckbox = fxCheckbox;
	self.effectField = fxField;
	x += 10;

	NSButton *argCheckbox; NSTextField *argField;
	x = [self addToggleFieldAtX:&x toStrip:strip
						   title:NSLocalizedString(@"Arg", @"argument stamp toggle")
						 enabled:self.gridView.writesArgument value:self.gridView.defaultArgument
					enableAction:@selector(argumentEnableChanged:) valueAction:@selector(argumentValueChanged:)
						checkbox:&argCheckbox field:&argField];
	self.argumentCheckbox = argCheckbox;
	self.argumentField = argField;
	x += 14;

	// -[PPPatternObject setPatternSize:] used to just write the header field
	// alone, desyncing it from the actual Cmds allocation -- now that it
	// really reallocates (grow or shrink, preserving existing rows), this
	// is the only place in the app that can invoke it at all.
	x = [self addLabel:NSLocalizedString(@"Len:", @"pattern length label") atX:x toStrip:strip];
	self.lengthField = [self addNumberFieldAtX:&x toStrip:strip
										 value:self.gridView.pattern.patternSize ?: 64
										   min:1 max:256
										action:@selector(patternLengthChanged:)];

	[self.view addSubview:strip];
	self.controlStrip = strip;
}

- (IBAction)patternLengthChanged:(id)sender
{
	PPPatternObject *pattern = self.gridView.pattern;
	if (!pattern) {
		return;
	}
	NSInteger newSize = [self syncedValueFrom:sender];
	pattern.patternSize = (int)newSize;
	// pattern.patternSize's setter reallocates the same PPPatternObject in
	// place rather than replacing it, so PatternGridView's own didSet-driven
	// invalidateSize()/redraw (see its `pattern` property) never fires on
	// its own -- reassigning here is what actually triggers it.
	self.gridView.pattern = pattern;
	[[self resolvedDocument] updateChangeCount:NSChangeDone];
	[self.view.window makeFirstResponder:self.gridView];
}

/// A checkbox ("does typing a note also stamp this field?") paired with the
/// numeric value to stamp when it's on -- the same shape as Vol/FX/Arg's
/// underlying PPPatternGridView properties, just exposed as one control pair
/// each instead of the always-on Ins/Oct fields above.
- (CGFloat)addToggleFieldAtX:(CGFloat *)x toStrip:(NSView *)strip title:(NSString *)title
					  enabled:(BOOL)enabled value:(NSInteger)value
				 enableAction:(SEL)enableAction valueAction:(SEL)valueAction
					 checkbox:(NSButton **)checkboxOut field:(NSTextField **)fieldOut
{
	NSButton *checkbox = [NSButton checkboxWithTitle:title target:self action:enableAction];
	[checkbox sizeToFit];
	checkbox.frame = NSMakeRect(*x, 6, NSWidth(checkbox.frame), 18);
	checkbox.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
	[strip addSubview:checkbox];
	*checkboxOut = checkbox;
	*x += NSWidth(checkbox.frame) + 4;

	NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(*x, 5, 34, 21)];
	field.alignment = NSTextAlignmentRight;
	field.integerValue = value;
	field.target = self;
	field.action = valueAction;
	[strip addSubview:field];
	*fieldOut = field;
	*x += 34;

	return *x;
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

- (IBAction)volumeEnableChanged:(id)sender
{
	self.gridView.writesVolume = ([sender state] == NSControlStateValueOn);
	[self.view.window makeFirstResponder:self.gridView];
}

- (IBAction)volumeValueChanged:(id)sender
{
	NSInteger v = MAX(0, MIN(255, [sender integerValue]));
	[sender setIntegerValue:v];
	self.gridView.defaultVolume = (uint8_t)v;
	[self.view.window makeFirstResponder:self.gridView];
}

- (IBAction)effectEnableChanged:(id)sender
{
	self.gridView.writesEffect = ([sender state] == NSControlStateValueOn);
	[self.view.window makeFirstResponder:self.gridView];
}

- (IBAction)effectValueChanged:(id)sender
{
	NSInteger v = MAX(0, MIN(255, [sender integerValue]));
	[sender setIntegerValue:v];
	self.gridView.defaultEffect = (uint8_t)v;
	[self.view.window makeFirstResponder:self.gridView];
}

- (IBAction)argumentEnableChanged:(id)sender
{
	self.gridView.writesArgument = ([sender state] == NSControlStateValueOn);
	[self.view.window makeFirstResponder:self.gridView];
}

- (IBAction)argumentValueChanged:(id)sender
{
	NSInteger v = MAX(0, MIN(255, [sender integerValue]));
	[sender setIntegerValue:v];
	self.gridView.defaultArgument = (uint8_t)v;
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
	self.lengthField.integerValue = self.gridView.pattern.patternSize;
}

@end
