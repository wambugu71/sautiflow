#ifndef MP4_AAC_DECODER_H
#define MP4_AAC_DECODER_H

#include "miniaudio.h"

#ifdef __cplusplus
extern "C"
{
#endif

    // Custom decoding backend vtable for MP4/AAC using minimp4 and FAAD2
    extern ma_decoding_backend_vtable g_ma_decoding_backend_vtable_mp4_aac;

#ifdef __cplusplus
}
#endif

#endif // MP4_AAC_DECODER_H