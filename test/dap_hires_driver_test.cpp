#include <cassert>
#include <cstdio>
#include <cstring>
#include <string>

#include "dap_hires_driver.h"

using namespace sautiflow::dap;

static void test_fiio_detection() {
    auto res = detectDapProfile("FiiO", "FiiO", "M17", "m17", "qcom", "kona", "");
    assert(res.isDapDetected);
    assert(res.profile.family == DapFamily::Fiio);
    assert(std::string(res.profile.modelName) == "FiiO M17");
    assert(res.profile.maxSampleRate == 768000);
    assert(res.profile.preferInt32);
    assert(res.profile.supportsDop);
    assert(res.profile.supportsNativeDsd);

    auto m23 = detectDapProfile("FiiO", "FiiO", "FiiO M23", "m23", "qcom", "bengal", "");
    assert(m23.isDapDetected);
    assert(m23.profile.family == DapFamily::Fiio);
    assert(std::string(m23.profile.modelName) == "FiiO M23");
    assert(m23.profile.maxSampleRate == 768000);
}

static void test_hiby_detection() {
    auto res = detectDapProfile("HiBy", "HiBy", "HiBy R6 III", "r6iii", "qcom", "bengal", "");
    assert(res.isDapDetected);
    assert(res.profile.family == DapFamily::HiBy);
    assert(std::string(res.profile.audioManagerParams) == "hiby_direct=on");
    assert(res.profile.maxSampleRate == 768000);

    auto rs8 = detectDapProfile("HiBy", "HiBy", "RS8", "rs8", "qcom", "", "");
    assert(rs8.isDapDetected);
    assert(std::string(rs8.profile.modelName) == "HiBy RS6 / RS8");
}

static void test_ibasso_shanling_cayin_ak() {
    auto ib = detectDapProfile("iBasso", "iBasso", "DX320", "dx320", "qcom", "", "");
    assert(ib.isDapDetected && ib.profile.family == DapFamily::IBasso);
    assert(ib.profile.maxSampleRate == 768000);

    auto sh = detectDapProfile("Shanling", "Shanling", "M8", "m8", "qcom", "", "");
    assert(sh.isDapDetected && sh.profile.family == DapFamily::Shanling);
    assert(sh.profile.maxSampleRate == 768000);

    auto cy = detectDapProfile("Cayin", "Cayin", "N8ii", "n8ii", "qcom", "", "");
    assert(cy.isDapDetected && cy.profile.family == DapFamily::Cayin);
    assert(std::string(cy.profile.modelName) == "Cayin N8ii");

    auto ak = detectDapProfile("iriver", "Astell&Kern", "SP3000", "sp3000", "", "", "");
    assert(ak.isDapDetected && ak.profile.family == DapFamily::AstellKern);
    assert(ak.profile.maxSampleRate == 768000);
}

static void test_sony_walkman_and_lg_quad_dac() {
    auto sony = detectDapProfile("Sony", "Sony", "NW-ZX707", "nw_zx707", "qcom", "", "");
    assert(sony.isDapDetected);
    assert(sony.profile.family == DapFamily::SonyWalkman);
    assert(std::string(sony.profile.modelName) == "Sony NW-ZX507 / ZX707");
    assert(sony.profile.maxSampleRate == 384000);

    // Non-Walkman Sony phone should NOT match Walkman DAP
    auto xperia = detectDapProfile("Sony", "Sony", "XQ-DQ72", "pdx234", "qcom", "kalama", "");
    assert(!xperia.isDapDetected);

    // LG Quad DAC
    auto lg = detectDapProfile("LGE", "lge", "LM-V600", "timelm", "qcom", "kona", "");
    assert(lg.isDapDetected);
    assert(lg.profile.family == DapFamily::LgQuadDac);
    assert(std::string(lg.profile.audioManagerParams) == "hifi_dac=on");
}

static void test_generic_phone_and_overrides() {
    auto pixel = detectDapProfile("Google", "google", "Pixel 8 Pro", "husky", "tensor", "zuma", "");
    assert(!pixel.isDapDetected);
    assert(pixel.profile.family == DapFamily::Generic);

    auto ovr = detectCurrentDapProfile(static_cast<int>(DapFamily::SonyWalkman));
    assert(ovr.isDapDetected);
    assert(ovr.profile.family == DapFamily::SonyWalkman);
    assert(ovr.profile.maxSampleRate == 384000);
}

int main() {
    test_fiio_detection();
    test_hiby_detection();
    test_ibasso_shanling_cayin_ak();
    test_sony_walkman_and_lg_quad_dac();
    test_generic_phone_and_overrides();
    std::printf("All DAP Hi-Res Driver unit tests PASSED.\n");
    return 0;
}
