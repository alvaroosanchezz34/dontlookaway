# Tienda premium (Robux): cómo activarla

La tienda premium está programada, pero **ningún artículo se puede comprar
todavía**: faltan los identificadores reales de Roblox. Mientras un ID sea `0`,
el artículo aparece como **PENDING SETUP**, el botón no hace nada y el
servidor rechaza cualquier intento de compra. No se simula ninguna compra.

Todo se configura en un único archivo:
`src/shared/Config/Monetization.luau`.

## Qué se vende

Todo es cosmético o un agradecimiento. **Nunca** se venden con Robux el
equipamiento, los Echoes ni las mejoras. Tampoco hay recompensas aleatorias.

| Clave | Tipo | Qué da |
|---|---|---|
| `VIP` | Game Pass | Título Patron, linterna Silver Lantern, estela Void, interfaz Frost |
| `FlashlightCollection` | Game Pass | Acabados de linterna Noir y Faded Rose |
| `EmotePack` | Game Pass | Gestos Hush y Bow |
| `SKIN_CANDLE` | Developer Product (una vez) | Acabado de linterna Candlelight |
| `SKIN_ASHEN` | Developer Product (una vez) | Acabado de linterna Ashen |
| `SUPPORT` | Developer Product (repetible) | Agradecimiento; el primero da el título Supporter y la insignia Lit Candle |

## Pasos en Creator Dashboard

La experiencia tiene que estar publicada (los productos pertenecen a una
experiencia). Si el juego es del grupo **Unreality Works**, crea los productos
desde la experiencia del grupo.

### Game Passes (VIP, FlashlightCollection, EmotePack)

1. Entra en <https://create.roblox.com/dashboard/creations> y abre la experiencia.
2. Ve a **Monetization → Passes** y pulsa **Create a Pass**.
3. Pon el nombre y la descripción (puedes copiar los de `Monetization.luau`) y
   una imagen. Guarda.
4. Abre el pase, ve a **Sales**, activa **Item for Sale** y elige el precio en
   Robux. El precio solo se decide aquí; el juego lo lee de Roblox.
5. Copia el **Pass ID** (el número en la URL o en los detalles del pase).
6. En `Monetization.luau`, cambia `id = 0` por ese número en la entrada con
   esa `key`.

### Developer Products (SKIN_CANDLE, SKIN_ASHEN, SUPPORT)

1. En la misma experiencia, ve a **Monetization → Developer Products** y pulsa
   **Create a Developer Product**.
2. Pon nombre, descripción, imagen y precio. Guarda.
3. Copia el **Product ID**.
4. En `Monetization.luau`, cambia `id = 0` por ese número en la entrada con
   esa `key`.

### Después

1. Sincroniza con Rojo y publica cuando decidas. Nada se publica automáticamente.
2. Las compras de Developer Products solo funcionan en la experiencia
   publicada o en Studio con **Game Settings → Security → Allow HTTP Requests**
   y **Enable Studio Access to API Services** activados. En Studio, Roblox
   muestra una compra de prueba que no cobra.

## Cómo funciona por dentro

- **Un solo `ProcessReceipt`.** Solo lo asigna `MonetizationService`; una
  prueba automática falla si otro script lo asigna.
- **Idempotente.** Cada `PurchaseId` concedido se guarda en el perfil del
  jugador (`purchases`). Si Roblox repite un recibo, se confirma sin conceder
  otra vez.
- **Confirmación solo tras guardar.** El recibo se confirma
  (`PurchaseGranted`) solo después de guardar el perfil en el DataStore
  (`DataService:SaveNow`). Si el guardado falla, la concesión se deshace en
  memoria y se devuelve `NotProcessedYet`, así que Roblox lo reintenta más
  tarde.
- **Perfiles temporales.** Si el DataStore falló al cargar al jugador, el
  servidor no abre la compra de productos (no se cobraría algo que no se puede
  guardar).
- **Game Passes.** Al cerrarse la ventana de compra, el servidor vuelve a
  preguntar a Roblox (`UserOwnsGamePassAsync`). Nunca se fía solo de la
  señal "purchased".
- **El cliente solo pide.** Envía `Premium "prompt" <key>`. Nunca dice qué
  compró: el resultado llega del servidor (`PremiumResult`).
- **Cuándo se puede comprar.** Solo desde el menú o el Field Office, nunca en
  mitad de una noche, para evitar compras accidentales.

## Comprobar en Studio

1. Con los IDs puestos, abre el menú, entra en **PREMIUM STORE** y comprueba
   que cada artículo muestra su precio real en Robux.
2. Compra un producto (en Studio es una compra de prueba). Debe aparecer
   "Thank you. Added to your wardrobe…" y el artículo debe salir en
   **SUPPLY ROOM → COSMETICS** como OWNED.
3. Vuelve a abrir la tienda: un acabado ya comprado sale como OWNED y no se
   puede comprar otra vez.
4. Cancela una compra: debe aparecer "Purchase cancelled." y el botón vuelve a
   BUY.
