# Realistic Clutch & Drivetrain C-Physics Pro for Assetto Corsa & CSP

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-Assetto%20Corsa%20%7C%20CSP%200.2.0%2B-blue.svg)](https://acstuff.ru/)
[![Physics](https://img.shields.io/badge/Physics-Discrete%20Stick--Slip%20%40%20333Hz-red.svg)]()
[![FFB](https://img.shields.io/badge/FFB-DirectInput%20Haptics%20333Hz-green.svg)]()
[![IPC](https://img.shields.io/badge/IPC-ac.connect%20Shared%20Memory%20%3C2ns-purple.svg)]()

**Realistic Clutch Pro** is an advanced, discrete-numerical manual clutch, flywheel kinetic momentum, and mechanical drivetrain physics simulation mod for **Assetto Corsa** powered by **Custom Shaders Patch (CSP)**.

Operating via a non-smooth Coulomb/Stribeck stick-slip mechanics solver with exact zero-crossing impulse projection and injecting directly into low-level CSP C++ physics hooks (`ac.overrideSpecificValue` with `DrivetrainClutchOverride`, `DrivetrainOpenThreshold`, and `ac.overrideEngineTorque`), it provides a genuine mechanical clutch feel with real stalling, true bite-zone friction chatter, hill balance, and 333 Hz DirectInput FFB haptics.

---

## Key Features

- **Non-Smooth Stick-Slip Discrete Numerical Mechanics:**
  - True 2-DoF slipping $\leftrightarrow$ 1-DoF locked state transitions.
  - Continuous Stribeck friction curve ($\mu_k \to \mu_s$) with viscous damping.
  - Exact zero-crossing impulse-momentum projection eliminating numerical limit-cycle oscillations (exact $0.000000\,\text{rad/s}$ relative slip when locked).
- **Almen-László Belleville Diaphragm & Marcel Cushion Spring:**
  - Realistic multi-stage clamping force $F_N(x)$ reproducing the physical pedal bite zone ($F_M = k_1 x_m + k_2 x_m^3$).
- **Multi-Stage Clutch Hub Torsional Damper Springs:**
  - Absorbs engine combustion pulses in locked state (Stage 1 idle rattle $k_1$, Stage 2 drive stiffness $k_2$, Coulomb hysteresis $T_{hys}$).
- **2-Node Thermal Network:**
  - Real-time heat dissipation ($\dot{Q}_{\text{gen}} = |\tau| \cdot |\Delta\omega|$) and thermal fade under clutch abuse.
- **Reflected Inertia & Road Load Dynamics:**
  - Dynamically calculates reflected drivetrain inertia $I_t(G)$ and road load resistance (gravity slope $m g \sin\theta$, aerodynamic drag, rolling friction, brake clamp).
- **Zero-Latency (<2ns) IPC Shared Memory Bridge (`ac.connect`):**
  - Instantaneous C-struct communication between the simulation app and the 333 Hz FFB post-processing thread.
- **333 Hz DirectInput FFB Post-Processing Middleware:**
  - **Driveline Macro-Judder (8–14 Hz):** Torsional driveline resonance under high launch load or steep hills.
  - **Friction Micro-Chatter (25–45 Hz):** Tactile lining micro-slip and surface grit texture.
  - **Combustion Order Harmonics:** 1.5, 2.0, 3.0, 4.0 harmonics matching engine cylinder count.
  - **Pre-Stall Lugging Bucking (5–7 Hz) & Underdamped Recoil Shock ($e^{-\lambda t}\sin(\omega t)$):** Violent mechanical reaction upon engine stall.
  - **Autonomous Fallback Watchdog:** Seamless standalone operation even if the UI app is closed.
- **Realistic Bump-Starting ("Pegar no Tranco"):**
  - Allows rolling starts down hills or with vehicle momentum when popping the clutch in gear with ignition ON.
- **Intelligent Automatic Vehicle Detection:**
  - Built-in presets for City Compacts (Fiat 500, Uno, Gol), Standard Road Cars (Fiesta ST, Golf, Civic), Turbodiesels (Hilux, Ranger, TDI), Sports Cars (BMW M3, Porsche 911), and Race Multiplate setups.
- **100% Universal Compatibility:**
  - Works on all Assetto Corsa manual cars without requiring unpacked `.acd` data files.

---

## Mathematical Formulation

### 1. Stribeck Continuous Friction
$$\mu(\Delta\omega, T) = \mu_{\text{fade}}(T) \cdot \left[ \mu_k + (\mu_s - \mu_k) \exp\left( -\left( \frac{|\Delta\omega|}{\omega_{\text{str}}} \right)^{\delta_{\text{str}}} \right) + \sigma_v |\Delta\omega| \right]$$

### 2. Zero-Crossing Impulse Projection (Anti-Chatter)
When the solver detects relative slip velocity zero-crossing within time step $\Delta t$:
$$\omega_c^{k+1} = \frac{I_e \omega_e^k + I_t \omega_t^k + (\tau_{\text{ext}, e} - \tau_{\text{load}})\Delta t}{I_e + I_t}$$
The system transitions seamlessly from 2 Degrees of Freedom to 1 Degree of Freedom with identically zero velocity oscillation.

### 3. Marcel Cushion Compression Curve
$$F_M(x_m) = k_1 x_m + k_3 x_m^3$$

---

## Directory Structure

```
RealisticClutchPro/
├── apps/
│   └── lua/
│       └── RealisticClutchPro/
│           ├── manifest.ini             # App definition & UI registration
│           ├── RealisticClutchPro.lua   # Main orchestrator & CSP C++ hooks
│           ├── cphys_core.lua           # Discrete Stick-Slip numerical solver
│           ├── drivetrain_model.lua     # Reflected inertia & road load equations
│           ├── clutch_shared_struct.lua # Zero-latency IPC shared memory layout
│           ├── presets.lua              # Vehicle database & auto-detector
│           ├── ui_components.lua        # Telemetry widgets & live curve plotting
│           ├── ffb_engine.lua           # FFB preview calculations
│           └── audio_engine.lua         # Starter & stall sound synthesizer
└── extension/
    └── lua/
        └── ffb-postprocess/
            └── RealisticClutchFFB/
                ├── manifest.ini         # CSP FFB Tweaks registration
                ├── settings.ini         # Gain parameters for Content Manager
                ├── clutch_shared_struct.lua # Zero-latency IPC shared memory layout
                └── ffb.lua              # 333 Hz DirectInput FFB post-processor
```

---

## Installation

1. Copy the `apps` and `extension` folders directly into your root Assetto Corsa installation directory:
   `...\steamapps\common\assettocorsa\`
2. In **Content Manager**:
   - Go to **Settings > Custom Shaders Patch > FFB Tweaks**.
   - Enable **Active post-processing script** and select **RealisticClutchFFB**.
3. In-game:
   - Enable **Realistic Clutch Pro** and **Clutch HUD Overlay** from the right-hand side app shelf.
   - Map your starter motor key or wheel button (default: Button 1 / X on PCYES W270 or keyboard `E`).

---

## License

MIT License. Developed by Antigravity.
