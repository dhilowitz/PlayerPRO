//
//  PPDriver.h
//  PPMacho
//
//  Created by C.W. Betts on 11/28/12.
//
//

#ifndef __PLAYERPROKIT_PPDRIVER_H__
#define __PLAYERPROKIT_PPDRIVER_H__

#import <Foundation/Foundation.h>
#include <PlayerPROCore/MAD.h>
#include <PlayerPROCore/RDriver.h>
#import <PlayerPROKit/PPConstants.h>

@class PPLibrary;
@class PPMusicObject;

#define UNAVAILABLE_REASON(theReason) __attribute__((unavailable(theReason)))

NS_ASSUME_NONNULL_BEGIN

@interface PPDriver : NSObject
@property (nonatomic, strong, nullable) PPMusicObject *currentMusic;
@property (readonly, strong) PPLibrary *theLibrary;
@property (readonly) MADDriverSettings driverSettings;
@property NSTimeInterval musicPosition;
@property (getter = isExporting) BOOL exporting;
@property (readonly) NSTimeInterval totalMusicPlaybackTime;

- (nonnull instancetype)init UNAVAILABLE_REASON("PPDriver cannot be inited without a library");
- (nullable instancetype)initWithLibrary:(PPLibrary *)theLib error:(out NSError* __nullable __autoreleasing* __nullable)theErr;
- (nullable instancetype)initWithLibrary:(PPLibrary *)theLib settings:(inout nullable MADDriverSettings *)theSettings error:(out NSError* __nullable __autoreleasing* __nullable)theErr NS_DESIGNATED_INITIALIZER;

/*!
 *	@method changeDriverSettingsToSettings:
 *	@abstract changes the sound format used by the driver.
 *	@param theSett
 *		The new sound settings to use.
 *	@param error
 *		A pointer to an \c NSError object. On failure, is populated with an error in the \c PPMADErrorDomain
 *	@return \c YES if successful, otherwise <code>NO</code>.
 */
- (BOOL)changeDriverSettingsToSettings:(MADDriverSettings*)theSett error:(out NSError* __nullable __autoreleasing* __nullable)error NS_SWIFT_NAME(changeDriverSettings(to:));

/*!
 *	@method		reattachCurrentMusic
 *	@abstract	Re-runs the engine's attach step (MADAttachDriverToMusic) for
 *		whatever's already in currentMusic, without changing what's
 *		attached and without resetting playback position.
 *	@discussion	-setCurrentMusic: only calls MADAttachDriverToMusic when the
 *		music object actually changes. Modifying an already-attached
 *		PPMusicObject in place -- e.g. importing a new sample into a
 *		document that's already open -- writes through to the MADMusic
 *		struct correctly, but the engine has no other way to notice:
 *		MADAttachDriverToMusic is where per-attach engine state (channel/
 *		track setup, effect chains) gets (re)built, and it's specifically
 *		designed to be safely re-callable with the same music pointer
 *		(it checks whether the pointer actually changed before deciding
 *		whether to reset playback position). This is that re-call, exposed
 *		for exactly that situation.
 *	@return		NO if there is no currentMusic, or the engine reported an
 *		error; the association isn't broken either way.
 */
- (BOOL)reattachCurrentMusicWithError:(out NSError* __nullable __autoreleasing* __nullable)error NS_SWIFT_NAME(reattachCurrentMusic());

- (void)beginExport;
- (void)endExport;

- (void)cleanDriver NS_SWIFT_NAME(cleanDriver());
- (MADErr)stopDriver NS_SWIFT_NAME(stopDriver());

- (BOOL)directSaveToPointer:(void*)thePtr settings:(nullable MADDriverSettings*)theSett;
- (nullable NSData*)directSave;
@property (readonly) NSInteger audioDataLength;

- (MADErr)getMusicStatusWithCurrentTime:(long*)curTime totalTime:(long*)totTime NS_SWIFT_NAME(getMusicStatusTime(current:total:));
- (MADErr)setMusicStatusToCurrentTime:(long)curTime maximumTime:(long)maxV minimumTime:(long)minV NS_SWIFT_NAME(setMusicStatusTime(current:maximum:minimum:));

//This is the main one that gets called
- (MADErr)playSoundDataFromPointer:(const void*)theSnd withSize:(NSUInteger)sndSize fromChannel:(int)theChan amplitude:(short)amp bitRate:(unsigned int)rate isStereo:(BOOL)stereo withNote:(Byte)theNote withLoopStartingAt:(NSUInteger)loopStart andLoopLength:(NSUInteger)loopLen;

- (MADErr)playSoundDataFromPointer:(const void*)theSnd withSize:(NSUInteger)sndSize fromChannel:(int)theChan amplitude:(short)amp bitRate:(unsigned int)rate isStereo:(BOOL)stereo;
- (MADErr)playSoundDataFromPointer:(const void*)theSnd withSize:(NSUInteger)sndSize fromChannel:(int)theChan amplitude:(short)amp bitRate:(unsigned int)rate isStereo:(BOOL)stereo withNote:(Byte)theNote;
- (MADErr)playSoundDataFromPointer:(const void*)theSnd withSize:(NSUInteger)sndSize fromChannel:(int)theChan amplitude:(short)amp bitRate:(unsigned int)rate isStereo:(BOOL)stereo withLoopInRange:(NSRange)loopRange;
- (MADErr)playSoundDataFromPointer:(const void*)theSnd withSize:(NSUInteger)sndSize fromChannel:(int)theChan amplitude:(short)amp bitRate:(unsigned int)rate isStereo:(BOOL)stereo withNote:(Byte)theNote withLoopInRange:(NSRange)loopRange;
- (MADErr)playSoundDataFromPointer:(const void*)theSnd withSize:(NSUInteger)sndSize fromChannel:(int)theChan amplitude:(short)amp bitRate:(unsigned int)rate isStereo:(BOOL)stereo withLoopStartingAt:(NSUInteger)loopStart andLoopLength:(NSUInteger)loopLen;

- (MADErr)playSoundDataFromData:(NSData*)theSnd fromChannel:(int)theChan amplitude:(short)amp bitRate:(unsigned int)rate isStereo:(BOOL)stereo;
- (MADErr)playSoundDataFromData:(NSData*)theSnd fromChannel:(int)theChan amplitude:(short)amp bitRate:(unsigned int)rate isStereo:(BOOL)stereo withNote:(Byte)theNote;
- (MADErr)playSoundDataFromData:(NSData*)theSnd fromChannel:(int)theChan amplitude:(short)amp bitRate:(unsigned int)rate isStereo:(BOOL)stereo withLoopInRange:(NSRange)loopRange;
- (MADErr)playSoundDataFromData:(NSData*)theSnd fromChannel:(int)theChan amplitude:(short)amp bitRate:(unsigned int)rate isStereo:(BOOL)stereo withNote:(Byte)theNote withLoopInRange:(NSRange)loopRange;
- (MADErr)playSoundDataFromData:(NSData*)theSnd fromChannel:(int)theChan amplitude:(short)amp bitRate:(unsigned int)rate isStereo:(BOOL)stereo withLoopStartingAt:(NSUInteger)loopStart andLoopLength:(NSUInteger)loopLen;
- (MADErr)playSoundDataFromData:(NSData*)theSnd fromChannel:(int)theChan amplitude:(short)amp bitRate:(unsigned int)rate isStereo:(BOOL)stereo withNote:(Byte)theNote withLoopStartingAt:(NSUInteger)loopStart andLoopLength:(NSUInteger)loopLen;

#if 0
- (MADErr)playSoundDataFromData:(NSData*)theSnd withSize:(NSUInteger)sndSize fromChannel:(int)theChan amplitude:(short)amp bitRate:(unsigned int)rate isStereo:(BOOL)stereo;
#endif

@property (readonly) short availableChannel;

/*!
 *	@method play
 *	@abstract Plays the song loaded in <code>currentMusic</code>.
 *	@return An error type on failure, or \c MADNoErr on success.
 */
- (MADErr)play;

/*!
 *	@method pause
 *	@abstract Pauses the currently playing song.
 *	@return An error type on failure, or \c MADNoErr on success.
 */
- (MADErr)pause;

/*!
 *	@method stop
 *	@abstract Pauses the currently playing song and sets the position at
 *	the beginning of the song
 *	@return An error type on failure, or \c MADNoErr on success.
 */
- (MADErr)stop;

@property (readonly, getter=isPlayingMusic)		BOOL playingMusic;
@property (readonly, getter=isDonePlayingMusic) BOOL donePlayingMusic;
@property (getter=isPaused)						BOOL paused;

- (nullable PPMusicObject *)loadMusicFile:(NSString*)path NS_RETURNS_RETAINED;
- (nullable PPMusicObject *)loadMusicURL:(NSURL*)url NS_RETURNS_RETAINED;

#pragma mark - More in-depth modification of the driver:

- (MADChannel)channelAtIndex:(NSInteger)idx; //!< Read-only
@property short patternPosition;
@property short patternIdentifier;
@property short partitionPosition;
/// When set, playback restarts the pattern currently playing instead of
/// advancing to the next order-list entry when it ends -- checked only at
/// that one natural pattern-end site, so a song's own Dxx/Bxx pattern-break
/// effects still fire normally.
@property BOOL loopCurrentPattern;
/// 0 to 64
@property short volume;
/// Live ticks-per-row ("speed" in tracker terms). 1 to 31, the engine's
/// own Fxx effect argument split between a speed command (<32) and a
/// tempo one (>=32) -- see MADCheckSpeed/DoEffect. Reseeded from
/// PPMusicObject.defaultSpeed whenever playback restarts from the top;
/// not the same property, and not persisted anywhere on its own.
@property short speedTicksPerRow;
/// Live tempo in BPM ("finespeed" in tracker terms). 32 to 255, the
/// complementary half of the same Fxx argument range as
/// -speedTicksPerRow. See PPMusicObject.defaultTempo.
@property short tempoBPM;
@property BOOL usesEqualizer;
@property (readonly, nullable) void *oscilloscopePointer NS_RETURNS_INNER_POINTER;
@property (readonly) size_t oscilloscopeSize;
- (BOOL)isChannelActiveAtIndex:(NSInteger)idx;
- (void)setChannelAtIndex:(NSInteger)idx toActive:(BOOL)enabled NS_SWIFT_NAME(setChannel(at:toActive:));

//! 0 to 64. Backed by the current music's header->chanVol[idx] -- read live
//! every mix tick (DoVolPanning256, Interrupt.c), so a change here is heard
//! immediately, including on already-sounding notes.
- (short)volumeAtTrackIndex:(NSInteger)idx NS_SWIFT_NAME(volume(atTrack:));
- (void)setVolume:(short)volume atTrackIndex:(NSInteger)idx NS_SWIFT_NAME(setVolume(_:atTrack:));

//! 0 to 64. Backed by the current music's header->chanPan[idx] -- unlike
//! volume, this is only read when a note is TRIGGERED on that track
//! (Interrupt.c), not continuously, so a change here affects the next note
//! played on that track rather than any note already sounding.
- (short)panAtTrackIndex:(NSInteger)idx NS_SWIFT_NAME(pan(atTrack:));
- (void)setPan:(short)pan atTrackIndex:(NSInteger)idx NS_SWIFT_NAME(setPan(_:atTrack:));

//! 0 to 64, decaying towards 0 when a track is silent. A lightweight,
//! already-computed-per-mix-tick gain snapshot (not true post-mix RMS) --
//! suitable for a VU-style activity meter, not a precise level meter.
- (short)activityAtTrackIndex:(NSInteger)idx NS_SWIFT_NAME(activity(atTrack:));

@end

@interface PPDriver (deprecated)
- (BOOL)isDonePlaying DEPRECATED_ATTRIBUTE;

- (NSInteger)audioLength DEPRECATED_ATTRIBUTE;
@end

NS_ASSUME_NONNULL_END

__BEGIN_DECLS
extern NSDictionary<PPLibraryInfoKeys,id> * __nonnull PPMADInfoRecToDictionary(MADInfoRec infoRec);
__END_DECLS


#endif
