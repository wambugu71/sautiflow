#include <curl/curl.h>
#include <iostream>

int main()
{
    std::cout << "Hello Curl" << std::endl;
    CURL *curl = curl_easy_init();
    if (curl)
    {
        std::cout << "Curl init success" << std::endl;
        curl_easy_cleanup(curl);
    }
    else
    {
        std::cout << "Curl init failed" << std::endl;
    }
    return 0;
}
