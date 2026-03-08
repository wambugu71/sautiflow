#include <stdio.h>
#include <stdlib.h>
#define MINIMP4_IMPLEMENTATION
#include "third_party/minimp4.h"

int read_callback(int64_t offset, void *buffer, size_t size, void *token)
{
    FILE *f = (FILE *)token;
    fseek(f, offset, SEEK_SET);
    return fread(buffer, 1, size, f) == size;
}

int main()
{
    FILE *f = fopen("C:\\Users\\wambugukinyua\\Downloads\\iLoveYt.net_YouTube_Naughty-Boy-Sam-Smith-La-la-la-Lyrics_Media_2WmBa1CviYE_008_128k (1).m4a", "rb");
    if (!f)
    {
        printf("Failed to open file\n");
        return 1;
    }

    fseek(f, 0, SEEK_END);
    int64_t size = ftell(f);
    fseek(f, 0, SEEK_SET);

    MP4D_demux_t mp4 = {0};
    int res = MP4D_open(&mp4, read_callback, f, size);
    printf("MP4D_open result: %d\n", res);
    if (res)
    {
        printf("Tracks: %d\n", mp4.track_count);
        for (int i = 0; i < mp4.track_count; i++)
        {
            printf(" Track %d: type=%d, samples=%d\n", i, mp4.track[i].handler_type, mp4.track[i].sample_count);
        }
    }
    fclose(f);
    return 0;
}