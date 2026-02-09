#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
#include <iostream>

int main()
{
    std::cout << "Hello Miniaudio" << std::endl;
    ma_encoder_config config = ma_encoder_config_init(ma_encoding_format_wav, ma_format_f32, 2, 44100);
    std::cout << "Config initialized" << std::endl;
    return 0;
}
