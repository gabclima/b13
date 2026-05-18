/*
 * ESP32 UART Bridge — AmlBoot
 * --------------------------------------------------------------------
 * Bridge entre o serial USB do PC e a UART do u-boot da TV box BTV B13.
 * Permite acessar o prompt `sc2_ah212#` do u-boot vendor via Serial Monitor.
 *
 * Wiring:
 *   ESP32 GND      ↔  BTV GND
 *   ESP32 GPIO16   ↔  BTV TX  (ESP32 RX2 lê o que a BTV manda)
 *   ESP32 GPIO17   ↔  BTV RX  (ESP32 TX2 envia comandos pra BTV)
 *
 *   NÃO conectar VCC/3.3V entre ESP32 e BTV — alimentação separada.
 *
 * Baud rate: 115200 8N1 (padrão do u-boot Amlogic SC2)
 *
 * Modo de uso:
 *   1. Upload deste sketch no ESP32 via Arduino IDE
 *   2. Conecte ESP32 no PC via USB
 *   3. Abra Serial Monitor a 115200 baud
 *   4. Ligue a BTV (toothpick + power)
 *   5. Quando aparecer "Hit any key to stop autoboot", digite qualquer
 *      tecla no Serial Monitor pra interceptar o u-boot
 *   6. Cai no prompt sc2_ah212#
 *
 * NOTA: Esta é uma versão simples "bridge". A versão "Auto-Intercept v2"
 * usada no projeto original detecta a janela de boot automaticamente e
 * manda Enter sozinho — útil porque a janela é muito curta (milissegundos).
 * Adapte conforme necessário.
 * --------------------------------------------------------------------
 */

#define UART_BAUD 115200
#define RX_PIN 16   // ESP32 RX2 — recebe da BTV TX
#define TX_PIN 17   // ESP32 TX2 — envia pra BTV RX

void setup() {
    // Serial0 = USB (pro PC), Serial2 = UART hardware do ESP32 pra BTV
    Serial.begin(UART_BAUD);
    Serial2.begin(UART_BAUD, SERIAL_8N1, RX_PIN, TX_PIN);

    Serial.println();
    Serial.println("=== ESP32 UART Bridge ===");
    Serial.print(">>> Baud: ");
    Serial.println(UART_BAUD);
    Serial.println(">>> RX2: GPIO16  TX2: GPIO17");
    Serial.println(">>> Aguardando dados da BTV...");
    Serial.println();
}

void loop() {
    // BTV -> PC (mostra o que o u-boot/kernel manda)
    while (Serial2.available()) {
        Serial.write(Serial2.read());
    }
    // PC -> BTV (envia comandos que você digita no Serial Monitor)
    while (Serial.available()) {
        Serial2.write(Serial.read());
    }
}

/*
 * Versão "Auto-Intercept" — descomentar e usar em vez do loop() acima
 * se a janela de "Hit any key" for muito rápida pra digitar manualmente.
 *
 * Detecta a string específica e manda Enter automaticamente.
 *
void loop() {
    static String buffer = "";
    static bool intercepted = false;

    // BTV -> PC + detecção
    while (Serial2.available()) {
        char c = Serial2.read();
        Serial.write(c);
        if (!intercepted) {
            buffer += c;
            if (buffer.length() > 200) buffer = buffer.substring(100);
            // String exata varia por u-boot — ajustar conforme necessário
            if (buffer.indexOf("Hit any key to stop autoboot") >= 0) {
                // Manda spam de Enter pra garantir intercept
                for (int i = 0; i < 50; i++) {
                    Serial2.write('\r');
                    delay(2);
                }
                intercepted = true;
                Serial.println("\n>>> INTERCEPT v2 <<<\n");
            }
        }
    }
    while (Serial.available()) {
        Serial2.write(Serial.read());
    }
}
*/
