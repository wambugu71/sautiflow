with open(r'c:\Users\wambugukinyua\miniaudiodart\mp4_aac_decoder.cpp', 'r', encoding='utf-8') as f:
    content = f.read()

old = 'const int64_t file_size = INT64_MAX;'
new = r"""int64_t file_size = INT64_MAX; // safe fallback
    {
        // Seek to end to get real file size so minimp4's EOF guard fires correctly
        // for moov-at-end M4A files. ma_seek_origin_end is supported by the
        // default VFS even though miniaudio's decoder pipeline doesn't normally use it.
        ma_result seekOk = onSeek(pReadSeekTellUserData, 0, ma_seek_origin_end);
        if (seekOk == MA_SUCCESS && onTell != NULL)
        {
            ma_int64 pos = 0;
            if (onTell(pReadSeekTellUserData, &pos) == MA_SUCCESS)
            {
                file_size = (int64_t)pos;
                mp4_log("[mp4_aac] file_size=%lld\n", (long long)file_size);
            }
        }
        // Seek back to start for minimp4
        onSeek(pReadSeekTellUserData, 0, ma_seek_origin_start);
    }"""

if old in content:
    content = content.replace(old, new, 1)
    with open(r'c:\Users\wambugukinyua\miniaudiodart\mp4_aac_decoder.cpp', 'w', encoding='utf-8') as f:
        f.write(content)
    print('Done: replaced INT64_MAX with real file size detection')
else:
    print('NOT FOUND - checking for variant...')
    # Check what is near that area
    idx = content.find('file_size = INT64_MAX')
    print(f'  found "file_size = INT64_MAX" at index {idx}')
    if idx >= 0:
        print(repr(content[idx-30:idx+60]))
