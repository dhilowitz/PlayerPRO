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
	[_currentDocument removeObserver:self forKeyPath:@"theMusic" context:kMusicContext];
}

- (void)awakeFromNib
{
	[super awakeFromNib];

	if (self.gridView) {
		return;		// awakeFromNib can be sent more than once
	}

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

	[_currentDocument addObserver:self
					   forKeyPath:@"theMusic"
						  options:NSKeyValueObservingOptionInitial
						  context:kMusicContext];
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
	PPMusicObject *music = self.currentDocument.theMusic;
	if (!music || music.patterns.count == 0) {
		self.gridView.pattern = nil;
		return;
	}

	self.gridView.trackCount = MAX(1, (NSInteger)music.totalTracks);
	self.gridView.pattern = music.patterns[0];
}

@end
