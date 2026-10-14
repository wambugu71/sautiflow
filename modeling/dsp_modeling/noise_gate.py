"""
Studio Noise Gate with Hysteresis & Hold Mathematical Modeling
==============================================================

Creators & Historical Foundations:
----------------------------------
- **Dual-Threshold Hysteresis Noise Gating**: Ivor Drawmer
  (Drawmer DS201 Dual Noise Gate, Drawmer Electronics Ltd, Yorkshire, UK, 1982).
- **VCA Voltage-Controlled Noise Attenuation**: David E. Blackmer
  (dbx Inc., Newton MA, 1970s).

Mathematical Principles
-----------------------
A classic single-threshold gate flutters or "chatters" rapidly when a decaying audio signal lingers
near the threshold point. The Drawmer dual-threshold hysteresis architecture eliminates chatter:

1. **Dual-Threshold State Machine with Hysteresis & Hold**:
   - **Open Threshold (T_open)**: Signal must exceed T_open to transition from CLOSED -> OPEN.
   - **Close Threshold (T_close)**: Signal must drop below T_close (< T_open) to trigger the HOLD timer.
   - **Hold Timer**: Holds gate fully open (gain = 1.0) for a configured duration (e.g. 50–200 ms)
     after dropping below T_close, guaranteeing trailing vocal breaths and natural instrument decays
     are never abruptly truncated.
   - **Release Phase**: Once the hold timer expires, gain smoothly decays toward the noise floor (e.g. -80 dB).

2. **2nd-Order Butterworth Sidechain High-Pass Filter**:
   Rejects low-frequency HVAC rumble, mic stand thumps, and turntable rumble from keeping the gate open.

3. **Smooth Ballistics**:
   Prevents clicks or sudden DC steps on gate open/close:
       gain[n] = gain[n-1] + alpha_att * (1.0 - gain[n-1])     (Attack phase)
       gain[n] = gain[n-1] + alpha_rel * (floor - gain[n-1])   (Release phase)
"""

from enum import Enum
import numpy as np

from .biquad import make_biquad, BiquadFilterType


class GateState(str, Enum):
    CLOSED = "closed"
    HOLDING = "holding"
    OPEN = "open"


class NoiseGateDSP:
    """
    Studio-grade noise gate with dual-threshold hysteresis, hold timer, and sidechain HPF.
    """

    def __init__(
        self,
        sample_rate: float = 48000.0,
        open_threshold_db: float = -40.0,
        close_threshold_db: float = -46.0,
        hold_ms: float = 50.0,
        attack_ms: float = 1.0,
        release_ms: float = 80.0,
        sidechain_hpf_hz: float = 80.0,
        floor_db: float = -80.0
    ):
        self.sample_rate = float(sample_rate)
        self.open_threshold_db = float(open_threshold_db)
        self.close_threshold_db = float(close_threshold_db)
        self.hold_ms = float(hold_ms)
        self.attack_ms = float(attack_ms)
        self.release_ms = float(release_ms)
        self.sidechain_hpf_hz = float(sidechain_hpf_hz)
        self.floor_db = float(floor_db)

        self.reset()

    def reset(self):
        self.state = GateState.CLOSED
        self.hold_counter = 0
        self.hold_samples_total = int(round(self.hold_ms * 0.001 * self.sample_rate))

        self.open_threshold_lin = float(np.power(10.0, self.open_threshold_db / 20.0))
        self.close_threshold_lin = float(np.power(10.0, self.close_threshold_db / 20.0))
        self.floor_lin = float(np.power(10.0, self.floor_db / 20.0))

        self.current_gain = self.floor_lin
        self.sc_envelope = 0.0

        self.alpha_att = float(1.0 - np.exp(-1.0 / (self.sample_rate * (max(self.attack_ms, 0.1) * 0.001))))
        self.alpha_rel = float(1.0 - np.exp(-1.0 / (self.sample_rate * (max(self.release_ms, 1.0) * 0.001))))

        if self.sidechain_hpf_hz >= 20.0:
            self.sc_hpf = make_biquad(
                BiquadFilterType.HIGHPASS, self.sidechain_hpf_hz, q=0.7071, sample_rate=self.sample_rate
            )
        else:
            self.sc_hpf = None

    def process(self, signal: np.ndarray) -> np.ndarray:
        s = np.asarray(signal, dtype=np.float32)
        is_1d = (s.ndim == 1)
        if is_1d:
            s = np.column_stack([s, s])

        num_frames = s.shape[0]
        out = np.zeros_like(s)

        sc = self.sc_hpf.process(s) if self.sc_hpf is not None else s

        env = self.sc_envelope
        gain = self.current_gain
        state = self.state
        hold_count = self.hold_counter

        for i in range(num_frames):
            sc_mono = 0.5 * (abs(float(sc[i, 0])) + abs(float(sc[i, 1])))

            # Peak detector
            env += (self.alpha_att if sc_mono > env else self.alpha_rel) * (sc_mono - env)

            # State machine
            if env >= self.open_threshold_lin:
                state = GateState.OPEN
                hold_count = self.hold_samples_total
            elif env < self.close_threshold_lin:
                if state == GateState.OPEN:
                    state = GateState.HOLDING
                    hold_count = self.hold_samples_total
                elif state == GateState.HOLDING:
                    if hold_count > 0:
                        hold_count -= 1
                    else:
                        state = GateState.CLOSED

            # Target gain determination
            if state in (GateState.OPEN, GateState.HOLDING):
                target_gain = 1.0
                gain += self.alpha_att * (target_gain - gain)
            else:
                target_gain = self.floor_lin
                gain += self.alpha_rel * (target_gain - gain)

            out[i, 0] = s[i, 0] * gain
            out[i, 1] = s[i, 1] * gain

        self.sc_envelope = env
        self.current_gain = gain
        self.state = state
        self.hold_counter = hold_count

        return out[:, 0] if is_1d else out
