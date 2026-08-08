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

static void *kMusicContext = &kMusicContext;

@interface ClassicalViewController ()
@property (nonatomic, strong) NSScrollView *gridScrollView;
@property (nonatomic, strong) PPPatternGridView *gridView;
@property (nonatomic, weak) PPDocument *observedDocument;
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
}

- (void)viewDidLoad
{
	[super viewDidLoad];

	// The Classic tab's view arrives from the nib empty, so build the grid and
	// its scroller here rather than in Interface Builder.
	self.gridView = [[PPPatternGridView alloc] initWithFrame:NSZeroRect];

	NSScrollView *scroller = [[NSScrollView alloc] initWithFrame:self.view.bounds];
	scroller.hasVerticalScroller = YES;
	scroller.hasHorizontalScroller = YES;
	scroller.autohidesScrollers = NO;
	scroller.borderType = NSBezelBorder;
	scroller.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	scroller.documentView = self.gridView;
	[self.view addSubview:scroller];
	self.gridScrollView = scroller;

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
		self.observedDocument = doc;
	}
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
	PPMusicObject *music = [self resolvedDocument].theMusic;
	if (!music || music.patterns.count == 0) {
		self.gridView.pattern = nil;
		return;
	}

	self.gridView.editUndoManager = [self resolvedDocument].undoManager;
	self.gridView.trackCount = MAX(1, (NSInteger)music.totalTracks);
	self.gridView.pattern = music.patterns[0];
}

@end
