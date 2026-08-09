//
//  PPMusicObject.h
//  PPMacho
//
//  Created by C.W. Betts on 12/1/12.
//
//

#ifndef __PLAYERPROKIT_PPMUSICOBJECT_H__
#define __PLAYERPROKIT_PPMUSICOBJECT_H__

#import <Foundation/Foundation.h>
#include <PlayerPROCore/PlayerPROCore.h>

NS_ASSUME_NONNULL_BEGIN

@class PPDriver;
@class PPLibrary;
@class PPInstrumentObject;
@class PPSampleObject;
@class PPPatternObject;
@class PPFXBusObject;

@interface PPMusicObject : NSObject <NSCopying>
@property (readonly) NSInteger countOfPatterns;
@property (readonly) NSInteger lengthOfPartitions;
@property (readonly) NSInteger totalTracks;
@property (readonly, strong, nonatomic) NSArray<PPSampleObject*> *sDatas;
@property (readonly, strong, nonatomic) NSArray<PPInstrumentObject*> *instruments;
@property (readonly, strong, nonatomic) NSMutableArray<PPPatternObject*> *patterns;
@property (readonly, strong, nonatomic) NSMutableArray<PPFXBusObject*> *buses;
@property (readwrite, copy, null_resettable) NSString *title;
@property (readwrite, copy, null_resettable) NSString *information;
@property (readonly, weak, nullable) PPDriver *attachedDriver;

@property BOOL usesLinearPitchTable;
@property BOOL limitPitchToMODTable;
@property BOOL showsCopyright;
@property int newPitch;
@property int newSpeed;
@property MADByte generalPitch;
@property MADByte generalSpeed;
@property MADByte generalVolume;

/// The song's saved default ticks-per-row (header->speed), reseeded into
/// PPDriver.speedTicksPerRow every time playback restarts from the top.
/// NOT the same as -newSpeed/-generalSpeed, which control the Adaptators
/// window's unrelated overall playback-rate scalar (header->ESpeed /
/// header->generalSpeed) -- this is the actual tracker Speed value.
@property short defaultSpeed;
/// The song's saved default tempo in BPM (header->tempo), reseeded into
/// PPDriver.tempoBPM every time playback restarts from the top. See
/// -defaultSpeed.
@property short defaultTempo;

- (instancetype)init;

/// Creates a music object from the supplied MADK file ONLY
- (nullable instancetype)initWithURL:(NSURL *)url error:(out NSError* __nullable __autoreleasing* __nullable)error NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithPath:(NSString *)url error:(out NSError* __nullable __autoreleasing* __nullable)error;

/// Creates a music object from any supported tracker type.
- (nullable instancetype)initWithURL:(NSURL *)url library:(PPLibrary *)theLib error:(out NSError* __nullable __autoreleasing* __nullable)error;
- (nullable instancetype)initWithPath:(NSString *)url library:(PPLibrary *)theLib error:(out NSError* __nullable __autoreleasing* __nullable)error;

/// Creates a music object from the specified music type.
/// If the type isn't available, it returns nil.
- (nullable instancetype)initWithURL:(NSURL *)url type:(in const char*)type library:(PPLibrary *)theLib error:(out NSError* __nullable __autoreleasing* __nullable)error NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithPath:(NSString *)path type:(in const char*)type library:(PPLibrary *)theLib error:(out NSError* __nullable __autoreleasing* __nullable)error;
- (nullable instancetype)initWithURL:(NSURL *)url stringType:(NSString*)type library:(PPLibrary *)theLib error:(out NSError* __nullable __autoreleasing* __nullable)error;
- (nullable instancetype)initWithPath:(NSString *)path stringType:(NSString*)type library:(PPLibrary *)theLib error:(out NSError* __nullable __autoreleasing* __nullable)error;

/// Creates a music object from any supported tracker type, also attaching a driver to the music.
- (nullable instancetype)initWithURL:(NSURL *)url driver:(PPDriver *)theLib error:(out NSError* __nullable __autoreleasing* __nullable)error;
- (nullable instancetype)initWithPath:(NSString *)path driver:(PPDriver *)theLib error:(out NSError* __nullable __autoreleasing* __nullable)error;
- (nullable instancetype)initWithURL:(NSURL *)url type:(in const char*)type driver:(PPDriver *)theLib error:(out NSError* __nullable __autoreleasing* __nullable)error;
- (nullable instancetype)initWithPath:(NSString *)path type:(in const char*)type driver:(PPDriver *)theLib error:(out NSError* __nullable __autoreleasing* __nullable)error;
- (nullable instancetype)initWithURL:(NSURL *)url stringType:(NSString *)type driver:(PPDriver *)theDriv error:(out NSError* __nullable __autoreleasing* __nullable)error;
- (nullable instancetype)initWithPath:(NSString *)path stringType:(NSString*)type driver:(PPDriver *)theDriv error:(out NSError* __nullable __autoreleasing* __nullable)error;

/*!
 *	Initializes a music object based on a music struct, copying if specified.
 */
- (instancetype)initWithMusicStruct:(MADMusic*)theStruct copy:(BOOL)copyData NS_DESIGNATED_INITIALIZER;

/*!
 *	Initializes a music object based on a music struct, copying it.
 */
- (instancetype)initWithMusicStruct:(MADMusic*)theStruct;

+ (MADErr)info:(MADInfoRec*)theInfo fromTrackerAtURL:(NSURL*)thURL usingLibrary:(PPLibrary*)theLib;

/// Save music to a URL in MADK format.
- (BOOL)saveMusicToURL:(NSURL *)tosave error:(out NSError* __nullable __autoreleasing* __nullable)error;
- (BOOL)saveMusicToURL:(NSURL *)tosave compress:(BOOL)mad1Comp error:(out NSError* __nullable __autoreleasing* __nullable)error;

- (BOOL)exportMusicToURL:(NSURL *)tosave format:(NSString*)form library:(PPLibrary*)otherLib error:(out NSError* __nullable __autoreleasing* __nullable)error;

/// This method sets the music object as the playback music
- (void)attachToDriver:(PPDriver *)theDriv;

- (void)addInstrumentObject:(PPInstrumentObject *)object;
- (void)replaceObjectInInstrumentsAtIndex:(NSInteger)index withObject:(PPInstrumentObject *)object;
@property (readonly) NSInteger countOfInstruments;
- (PPInstrumentObject*)instrumentObjectAtIndex:(NSInteger)idx;
- (void)clearInstrumentsAtIndexes:(NSIndexSet *)indexes;
- (void)clearInstrumentObjectAtIndex:(NSInteger)index;

@property (readonly) MADMusic *internalMadMusicStruct NS_RETURNS_INNER_POINTER;

/// The order list: how many of the up-to-256 order-list positions are
/// part of the active playback sequence -- distinct from the number of
/// defined patterns (-countOfPatterns). A position holds a pattern ID,
/// which can repeat across positions or skip patterns entirely; nothing
/// about the order list changes what patterns exist, only what order (and
/// how often) they play in.
@property (nonatomic) NSInteger orderListLength;

/// The pattern ID (an index into -patterns) that order-list position
/// `index` currently points at. Valid range for `index` is 0..<256, the
/// same practical limit CreatePartiWindow's original UI enforced on
/// numPointers (oPointers itself is allocated for MAXPOINTER == 999, a
/// generous over-allocation, not a supported range).
- (MADByte)patternIDAtOrderListPosition:(NSInteger)index;
- (void)setPatternID:(MADByte)patternID atOrderListPosition:(NSInteger)index NS_SWIFT_NAME(setPatternID(_:atOrderListPosition:));

- (MADErr)exportInstrumentListToURL:(NSURL*)outURL;
- (BOOL)addInstrument:(PPInstrumentObject*)theIns;
- (BOOL)importInstrumentListFromURL:(NSURL *)insURL error:(out NSError * __nullable __autoreleasing*__nullable)theErr;

/// Appends a new, blank 64-row pattern (sized to the song's current channel
/// count) and returns the PPPatternObject wrapping it, or nil if the song
/// is already at the MAXPATTERN (200) cap. Not added to the order list --
/// a pattern existing and a pattern being scheduled to play are separate
/// concerns, same as everywhere else -orderListLength/-setPatternID:... are
/// used.
- (nullable PPPatternObject *)addPattern;

@end

NS_ASSUME_NONNULL_END

#endif
