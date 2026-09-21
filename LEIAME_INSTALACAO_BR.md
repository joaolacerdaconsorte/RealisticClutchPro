# 🚗 Realistic Clutch & Stalling Pro v3.0 (CSP Ultimate Drivetrain Simulation)

Mod avançado de física e simulação de embreagem manual realista, ponto de fricção com Force Feedback (FFB 1000Hz), corte cinético de motor com inércia de volante, arrancada suave no plano (Creep), equilíbrio em ladeira (Hill Hold), gravidade real e sistema de ignição/partida rápida para o **Assetto Corsa** com **Custom Shaders Patch (CSP)** e **Content Manager**.

---

## ✨ Principais Funcionalidades (v3.0)

1. **Acumulador Cinético de Inércia do Volante do Motor (Adeus Mortes Irreais):**
   - Substituição de cortes binários por cálculo contínuo de energia cinética do volante ($\int (T_{\text{combustão}} - T_{\text{resistência}}) dt$).
   - Janela de recuperação realista de 0.35s a 0.70s com engasgos sonoros e trepidação visual antes do estol definitivo.

2. **Governador de Marcha Lenta da ECU:**
   - Mantém marcha lenta firme e sem apagões em Ponto Morto (`N`) ou com embreagem pressionada em qualquer carro.

3. **Arrancada Suave no Plano (Creep de Marcha Lenta):**
   - Soltando a embreagem suavemente em 1ª marcha ou Ré sem acelerador, o carro anda sozinho a 6–9 km/h sem morrer.

4. **Ponto de Fricção com Curva OEM e FFB 1000Hz:**
   - Vibração de cilindros e trepidação metálica (*clutch chatter*) de 24–36Hz no volante ao acoplar na zona de fricção.

5. **Física de Ladeira Real (Hill Roll & Balanço):**
   - O carro desce livremente em neutro ou embreagem solta em subidas/descidas se não frear.
   - Ponto de equilíbrio real: segure o carro parado na rampa apenas equilibrando acelerador e embreagem.

6. **Mapeamentos de Controles (Volante PCYES W270 / Genérico):**
   - **Partida do Motor:** Botão **`X`** no volante (Botão 1 / `JOY=0 BUTTON=0` / Tecla `E`). 1 clique para ligar!
   - **Freio de Mão:** Botão **16** no câmbio (`JOY=0 BUTTON=15`).
   - **Câmbio H:** Marchas 1 a 6 e Ré (Botões 17 a 23).

7. **Auto-Detecção Universal de Carros (Presets Inteligentes):**
   - **Compactos Urbanos (Fiat 500 / Uno / Gol / Ka / 1.0L-1.4L):** Volante leve, ponto macio.
   - **Carro de Rua Médio (Fiesta ST / Golf / Civic / Miata / 1.6L-2.0L):** Equilíbrio perfeito.
   - **Turbodiesel (Hilux / Ranger / TDI):** Arrancada forte no torque puro.
   - **Esportivos / Performance (BMW M3 / Porsche 911 / Supra):** Engate preciso e vigoroso.
   - **Corrida / Multidisco (GT3 / Drift / Cup):** Embreagem direta on/off.

---

## 🛠️ Como Instalar

### Método 1: Instalação Automática via Content Manager
1. Arraste o arquivo `RealisticClutchPro_v1.0.0_ContentManager.zip` para dentro da janela do **Content Manager**.
2. Clique no ícone de três linhas verdes no canto superior direito do Content Manager e clique em **Install**.

### Método 2: Instalação Manual
Copie as seguintes pastas para a raiz do seu Assetto Corsa (`steamapps/common/assettocorsa/`):
- `apps/lua/RealisticClutchPro` -> `assettocorsa/apps/lua/RealisticClutchPro`
- `extension/lua/ffb-postprocess/RealisticClutchFFB` -> `assettocorsa/extension/lua/ffb-postprocess/RealisticClutchFFB`

---

## 🎮 Dicas Rápidas de Pilotagem
- **Para Ligar o Carro:** Pressione o botão **`X`** no volante PCYES W270 (ou tecla `E` no teclado).
- **Para Arrancar no Plano:** Engate a 1ª marcha e solte o pedal da embreagem progressivamente. O carro começará a rolar suavemente a 6–9 km/h.
- **Para Subida:** Segure o freio, traga a embreagem até sentir a vibração no volante e solte o freio acelerando levemente.
- **Se o Motor Morrer:** Pise na embreagem (ou coloque em Ponto Morto) e aperte **`X`** para religar instantaneamente.

---
*Desenvolvido com excelência técnica para máxima fidelidade e imersão automobilística no Assetto Corsa!*
