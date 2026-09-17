#pragma once

#include <string>
#include <vector>
#include <sstream>
#include <algorithm>
#include <cctype>
#include <fstream>
#include <cstdlib>

namespace sauti::dsp {

// Matches AEEqBandType in audio_engine.h
enum AutoEqBandType {
    AUTOEQ_BAND_PEAK = 0,
    AUTOEQ_BAND_BANDPASS = 1,
    AUTOEQ_BAND_NOTCH = 2,
    AUTOEQ_BAND_LOWSHELF = 3,
    AUTOEQ_BAND_HIGHSHELF = 4,
    AUTOEQ_BAND_LOWPASS = 5,
    AUTOEQ_BAND_HIGHPASS = 6,
    AUTOEQ_BAND_BELL = 7,
    AUTOEQ_BAND_TILT = 8,
    AUTOEQ_BAND_ALLPASS = 9
};

struct AutoEqBandDef {
    int type = AUTOEQ_BAND_PEAK;
    bool enabled = true;
    float frequencyHz = 1000.0f;
    float gainDb = 0.0f;
    float q = 1.0f;
    float slope = 1.0f;
};

struct AutoEqProfile {
    float preampDb = 0.0f;
    std::vector<AutoEqBandDef> bands;
    bool isValid = false;

    size_t bandCount() const { return bands.size(); }
};

class AutoEqParser {
public:
    // Parse an AutoEQ / EqualizerAPO formatted string
    static AutoEqProfile parseString(const std::string &content) {
        AutoEqProfile profile;
        std::istringstream stream(content);
        std::string line;

        while (std::getline(stream, line)) {
            parseLine(line, profile);
        }

        if (!profile.bands.empty()) {
            profile.isValid = true;
        }
        return profile;
    }

    // Parse an AutoEQ file directly from disk
    static AutoEqProfile parseFile(const std::string &filePath) {
        AutoEqProfile profile;
        std::ifstream file(filePath);
        if (!file.is_open()) {
            return profile;
        }

        std::string line;
        while (std::getline(file, line)) {
            parseLine(line, profile);
        }

        if (!profile.bands.empty()) {
            profile.isValid = true;
        }
        return profile;
    }

private:
    static std::string trim(const std::string &str) {
        size_t first = str.find_first_not_of(" \t\r\n");
        if (first == std::string::npos) return "";
        size_t last = str.find_last_not_of(" \t\r\n");
        return str.substr(first, (last - first + 1));
    }

    static std::string toUpper(std::string str) {
        for (char &c : str) {
            c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
        }
        return str;
    }

    static void parseLine(std::string line, AutoEqProfile &profile) {
        // Strip comments (#, ;, //)
        size_t commentPos = line.find('#');
        if (commentPos != std::string::npos) line = line.substr(0, commentPos);
        commentPos = line.find(';');
        if (commentPos != std::string::npos) line = line.substr(0, commentPos);
        commentPos = line.find("//");
        if (commentPos != std::string::npos) line = line.substr(0, commentPos);

        line = trim(line);
        if (line.empty()) return;

        std::string upperLine = toUpper(line);

        // Check for Preamp
        // e.g.: "Preamp: -6.5 dB" or "Preamp: -6.5"
        if (upperLine.rfind("PREAMP", 0) == 0) {
            size_t colonPos = upperLine.find(':');
            std::string valStr = (colonPos != std::string::npos) ? upperLine.substr(colonPos + 1) : upperLine.substr(6);
            std::istringstream valStream(valStr);
            float pVal = 0.0f;
            if (valStream >> pVal) {
                profile.preampDb = pVal;
            }
            return;
        }

        // Check for Filter definition
        // e.g.: "Filter 1: ON PK Fc 31 Hz Gain -4.2 dB Q 1.41"
        // or:   "Filter: ON LSC Fc 105 Gain 5.5 Q 0.71"
        if (upperLine.rfind("FILTER", 0) == 0) {
            size_t colonPos = line.find(':');
            std::string contentStr = (colonPos != std::string::npos) ? line.substr(colonPos + 1) : line.substr(6);

            std::istringstream iss(contentStr);
            std::vector<std::string> tokens;
            std::string token;
            while (iss >> token) {
                tokens.push_back(token);
            }

            if (tokens.size() < 2) return;

            AutoEqBandDef band;
            size_t idx = 0;

            // Optional ON / OFF status
            std::string firstTokUpper = toUpper(tokens[0]);
            if (firstTokUpper == "ON") {
                band.enabled = true;
                idx = 1;
            } else if (firstTokUpper == "OFF") {
                band.enabled = false;
                idx = 1;
            }

            if (idx >= tokens.size()) return;

            // Filter Type token
            std::string typeTok = toUpper(tokens[idx++]);
            if (typeTok == "PK" || typeTok == "PEAK" || typeTok == "BELL") {
                band.type = AUTOEQ_BAND_PEAK;
            } else if (typeTok == "LSC" || typeTok == "LS" || typeTok == "LOWSHELF" || typeTok == "LOW_SHELF") {
                band.type = AUTOEQ_BAND_LOWSHELF;
            } else if (typeTok == "HSC" || typeTok == "HS" || typeTok == "HIGHSHELF" || typeTok == "HIGH_SHELF") {
                band.type = AUTOEQ_BAND_HIGHSHELF;
            } else if (typeTok == "LP" || typeTok == "LPF" || typeTok == "LOWPASS" || typeTok == "LOW_PASS") {
                band.type = AUTOEQ_BAND_LOWPASS;
            } else if (typeTok == "HP" || typeTok == "HPF" || typeTok == "HIGHPASS" || typeTok == "HIGH_PASS") {
                band.type = AUTOEQ_BAND_HIGHPASS;
            } else if (typeTok == "BP" || typeTok == "BPF" || typeTok == "BANDPASS" || typeTok == "BAND_PASS") {
                band.type = AUTOEQ_BAND_BANDPASS;
            } else if (typeTok == "NO" || typeTok == "NOTCH") {
                band.type = AUTOEQ_BAND_NOTCH;
            } else if (typeTok == "TILT") {
                band.type = AUTOEQ_BAND_TILT;
            } else if (typeTok == "AP" || typeTok == "ALLPASS" || typeTok == "ALL_PASS") {
                band.type = AUTOEQ_BAND_ALLPASS;
            } else {
                band.type = AUTOEQ_BAND_PEAK;
            }

            // Parse key-value pairs (Fc, Gain, Q, etc.)
            while (idx < tokens.size()) {
                std::string key = toUpper(tokens[idx++]);
                if (idx >= tokens.size()) break;

                if (key == "FC" || key == "FREQ" || key == "FREQUENCY") {
                    float val = std::strtof(tokens[idx++].c_str(), nullptr);
                    if (val > 0.0f) band.frequencyHz = val;
                    // Skip optional "Hz" token
                    if (idx < tokens.size() && toUpper(tokens[idx]) == "HZ") idx++;
                } else if (key == "GAIN") {
                    float val = std::strtof(tokens[idx++].c_str(), nullptr);
                    band.gainDb = val;
                    // Skip optional "dB" token
                    if (idx < tokens.size() && toUpper(tokens[idx]) == "DB") idx++;
                } else if (key == "Q" || key == "Q-FACTOR") {
                    float val = std::strtof(tokens[idx++].c_str(), nullptr);
                    if (val > 0.0f) band.q = val;
                } else if (key == "SLOPE" || key == "S") {
                    float val = std::strtof(tokens[idx++].c_str(), nullptr);
                    if (val > 0.0f) band.slope = val;
                }
            }

            profile.bands.push_back(band);
        }
    }
};

} // namespace sauti::dsp
