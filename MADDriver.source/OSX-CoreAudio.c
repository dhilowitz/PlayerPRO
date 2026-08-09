/*
 *  Mac-CoreAudio.c
 *  PlayerPRO tryout
 *
 *  Created by C.W. Betts on 6/19/09.
 *  Copyright 2009 __MyCompanyName__. All rights reserved.
 *
 */

#include "RDriver.h"
#include "RDriverInt.h"
#include "MADPrivate.h"

// True if any channel currently has live sample data to render, regardless
// of Reading (the transport play/stop flag) -- lets a one-shot preview
// triggered via MADPlaySoundData (instrument list Play, piano keyboard, Box
// editor note audition) be heard while the transport is stopped, without
// letting the sequencer itself advance (that's still gated on Reading
// throughout Interrupt.c/NoteAnalyse).
static bool CAAnyChannelActive(MADDriverRec *theRec)
{
	for (int i = 0; i < theRec->MultiChanNo; i++) {
		if (!MADDriverChannelIsDonePlaying(theRec, i))
			return true;
	}
	return false;
}

//TODO: we should probably do something to prevent thread contention
static OSStatus CAAudioCallback(void						*inRefCon,
								AudioUnitRenderActionFlags	*ioActionFlags,
								const AudioTimeStamp		*inTimeStamp,
								UInt32						inBusNumber,
								UInt32						inNumberFrames,
								AudioBufferList				*ioData)
{
	size_t		remaining, len;
	AudioBuffer	*abuf;
	void		*ptr;
	UInt32		i = 0;

	MADDriverRec *theRec = (MADDriverRec*)inRefCon;
	// No top-of-callback blanket wipe here: CABuffer can hold a
	// still-pending, not-yet-copied-to-hardware remainder from the
	// previous refill (CABufOff < BufSize) even after Reading/
	// CAAnyChannelActive just went false -- e.g. a short preview note
	// (piano, instrument-list Play, box-editor audition) that finishes
	// mid-buffer. Unconditionally memset'ing the whole buffer here used
	// to destroy that pending tail before it could reach the speaker,
	// leaving only the already-copied attack transient audible (a
	// click, then silence). The per-refill "!didMix" branch below
	// already writes correct silence into CABuffer exactly when a fresh
	// chunk is actually needed, so nothing else has to happen here.
	for (i = 0; i < ioData->mNumberBuffers; i++) {
		abuf = &ioData->mBuffers[i];
		remaining = abuf->mDataByteSize;
		ptr = abuf->mData;
		while (remaining > 0) {
			if (theRec->CABufOff >= theRec->BufSize) {
				// Reading uses MADDirectSave, preserving its existing
				// musicEnd-driven auto-stop behavior exactly; a preview
				// while stopped uses MADDirectSaveAlways (an exact twin of
				// MADDirectSave minus its "return false while !Reading"
				// gate), since there's no song-end condition to honor when
				// nothing is actually playing. Re-checked here rather than
				// reusing the top-of-callback result, since a preview note
				// can finish mid-callback, between buffer refills.
				bool shouldMix = theRec->base.Reading || CAAnyChannelActive(theRec);
				bool didMix = theRec->base.Reading
					? MADDirectSave(theRec->CABuffer, NULL, theRec)
					: (shouldMix && MADDirectSaveAlways(theRec->CABuffer, NULL, theRec));
				if (!didMix) {
					switch(theRec->DriverSettings.outPutBits) {
						case 8:
							memset(theRec->CABuffer, 0x80, theRec->BufSize);
							break;

						case 16:
						default:
							memset(theRec->CABuffer, 0, theRec->BufSize);
							break;
					}
				}
				theRec->CABufOff = 0;
			}
			
			len = theRec->BufSize - theRec->CABufOff;
			if (len > remaining)
				len = remaining;
			memcpy(ptr, (char *)theRec->CABuffer + theRec->CABufOff, len);
			ptr = (char *)ptr + len;
			remaining -= len;
			theRec->CABufOff += len;
		}
	}
	
	/*if (BuffSize - pos > tickadd)	theRec->base.OscilloWavePtr = theRec->CABuffer + (int)pos;
	 else */
	theRec->base.OscilloWavePtr = theRec->CABuffer;
	return noErr;
}

MADErr initCoreAudio(MADDriverRec *inMADDriver)
{
	OSStatus result = noErr;
	struct AURenderCallbackStruct callback, blankCallback = {0};
	AudioComponentDescription theDes = {0};
	AudioStreamBasicDescription audDes = {0};
	int outChn;
	AudioComponent theComp;
	
	callback.inputProc = CAAudioCallback;
	callback.inputProcRefCon = inMADDriver;
	
	theDes.componentType = kAudioUnitType_Output;
#if TARGET_OS_IPHONE || TARGET_OS_TV
	theDes.componentSubType = kAudioUnitSubType_GenericOutput;
#else
	theDes.componentSubType = kAudioUnitSubType_DefaultOutput;
#endif
	theDes.componentManufacturer = kAudioUnitManufacturer_Apple;
	audDes.mFormatID = kAudioFormatLinearPCM;
	audDes.mFormatFlags = kLinearPCMFormatFlagIsPacked | kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian;
	
	switch (inMADDriver->DriverSettings.outPutMode) {
		case MonoOutPut:
			outChn = 1;
			break;
			
		case StereoOutPut:
		case DeluxeStereoOutPut:
		default:
			outChn = 2;
			break;
			
		case PolyPhonic:
			outChn = 4;
			break;
	}
	audDes.mChannelsPerFrame = outChn;
	audDes.mSampleRate = inMADDriver->DriverSettings.outPutRate;
	audDes.mBitsPerChannel = inMADDriver->DriverSettings.outPutBits;
	audDes.mFramesPerPacket = 1;
	audDes.mBytesPerFrame = audDes.mBitsPerChannel * audDes.mChannelsPerFrame / 8;
	audDes.mBytesPerPacket = audDes.mBytesPerFrame * audDes.mFramesPerPacket;
	
	theComp = AudioComponentFindNext(NULL, &theDes);
	if (theComp == NULL) {
		return MADSoundManagerErr;
	}
	result = AudioComponentInstanceNew(theComp, &inMADDriver->CAAudioUnit);
	if (result != noErr) {
		return MADSoundManagerErr;
	}
	
	result = AudioUnitSetProperty(inMADDriver->CAAudioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &audDes, sizeof(audDes));
	if (result != noErr) {
		AudioComponentInstanceDispose(inMADDriver->CAAudioUnit);
		return MADSoundManagerErr;
	}
	
	result = AudioUnitSetProperty(inMADDriver->CAAudioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof(callback));
	if (result != noErr) {
		AudioComponentInstanceDispose(inMADDriver->CAAudioUnit);
		return MADSoundManagerErr;
	}
	
	result = AudioUnitInitialize(inMADDriver->CAAudioUnit);
	if (result != noErr) {
		AudioComponentInstanceDispose(inMADDriver->CAAudioUnit);
		AudioUnitSetProperty(inMADDriver->CAAudioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &blankCallback, sizeof(blankCallback));
		return MADSoundManagerErr;
	}
	
	inMADDriver->CABufOff = inMADDriver->BufSize;
	inMADDriver->CABuffer = calloc(inMADDriver->BufSize, 1);
	
	result = AudioOutputUnitStart(inMADDriver->CAAudioUnit);
	if (result != noErr) {
		free(inMADDriver->CABuffer);
		AudioUnitSetProperty(inMADDriver->CAAudioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &blankCallback, sizeof(blankCallback));
		AudioComponentInstanceDispose(inMADDriver->CAAudioUnit);
		return MADSoundManagerErr;
	}
	return MADNoErr;
}

MADErr closeCoreAudio(MADDriverRec *inMADDriver)
{
	struct AURenderCallbackStruct callback = {0};
	
	OSStatus result = AudioOutputUnitStop(inMADDriver->CAAudioUnit);
	if (result != noErr) {
		
	}
	result = AudioUnitSetProperty(inMADDriver->CAAudioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof(callback));
	if (result != noErr) {
		
	}
	
	result = AudioComponentInstanceDispose(inMADDriver->CAAudioUnit);
	if (result != noErr) {
		
	}
	
	inMADDriver->base.OscilloWavePtr = NULL;
	if (inMADDriver->CABuffer) {
		free(inMADDriver->CABuffer);
	}
	
	return MADNoErr;
}
