# Auditoría del Creator Store para DON'T LOOK AWAY

> **Qué se ha podido hacer y qué no (léelo primero).**
>
> - **Studio:** en esta sesión no hay acceso a Roblox Studio.
> - **Red:** la red del entorno bloquea `*.roblox.com` desde la terminal y desde la descarga de páginas, así que no he podido abrir ni una ficha ni descargar ningún modelo.
> - **Lo que sí ha funcionado:** el **buscador web restringido a `create.roblox.com`**. De ahí salen:
>   - nombres e **IDs reales**, tomados de la URL de cada ficha;
>   - algunos datos del listado (creador, duración, valoraciones, conteos), copiados de los fragmentos del buscador. **Ningún dato está verificado en la ficha.**
> - **Ningún asset se ha insertado, inspeccionado ni probado.** Por eso ninguno está en «Integrar». Lo mejor que puede tener un candidato es «Probar en Studio».
> - **Herramienta nueva:** para que esa prueba sea segura y repetible he hecho `tools/audit_asset.luau`. Lee un modelo guardado desde Studio **sin ejecutar nada**, busca puertas traseras y dependencias, mide el coste y saca una copia sin scripts (§E, §G).

---

## A. Diagnóstico del proyecto

**Cómo está hecho Ashgrove.** Todo el mundo se **genera por código**:
- `MapBuilder` construye la arquitectura y `Props.luau` los muebles.
- `MaterialLibrary` pone los materiales propios (`MaterialVariant` con texturas de `assets/textures`).
- Los muebles se sustituyen en ejecución por **mallas propias hechas en Blender** (`assets/props`, `PropMeshes`).
- El Observer y el Mimic son rigs propios: `ObserverRig`, Motor6D con poses calculadas, sin animaciones de Humanoid.
- El sonido sale de muestras de Roblox procesadas más hojas de audio originales (`tools/gen_audio.py`).

**Dónde está de verdad el problema visual** (`docs/FALLOS_PENDIENTES.md`):
1. **§0 — los recursos propios no cargan.** Las mallas de los props, las texturas de materiales y las hojas de audio las subió **otra cuenta**. Tu place no las puede cargar, así que los muebles se quedan con las piezas de respaldo («plástico») y el audio original puede quedarse mudo.
   **Es la mejora visual número uno y no necesita ningún asset del Creator Store:** basta con volver a subir los archivos del repo desde tu cuenta o la del grupo.
2. **§6 — rugosidad mal horneada** en zócalos, cornisas y molduras: bordes brillantes. Se arregla en el pipeline de Blender.
3. **§8 — IDs de Decal en lugar de Image** en algunas texturas.

**Conclusión del diagnóstico:**
- El Creator Store **no** debe sustituir la arquitectura ni los muebles propios. Todo está hecho con una identidad coherente (misma piel de materiales, misma escala, mismo generador). Meter modelos gratuitos sueltos rompería esa coherencia y la generación procedural.
- Donde el catálogo **sí** aporta, con poco riesgo, es en el **audio**: hay sonido con licencia de Pro Sound Effects y APM publicado en el Store, sin scripts.
- Aporta además, en segundo lugar, en **unos pocos props de detalle** oficiales de Roblox, para cerca de cámara y para el marketing.

---

## B. Selección prioritaria

Todos los IDs salen de la URL oficial de la ficha (`create.roblox.com/store/asset/<ID>`). «Según el buscador» marca los datos que no he podido comprobar en la ficha.

### Audio (prioridad 1: sin scripts, sin geometría, mejora inmediata)

| Asset | ID | Creador | Datos (según el buscador) | Uso en DON'T LOOK AWAY |
|---|---|---|---|---|
| [Buzzing Fluorescent Light](https://create.roblox.com/store/asset/619993906/Buzzing-Fluorescent-Light) | 619993906 | @Dekimus | Efecto de sonido, 1:11 | Bucle del zumbido de tubos (pasillo imposible, salas con corriente) |
| [Eerie Ambience 1 (SFX)](https://create.roblox.com/store/asset/9112775175/Eerie-Ambience-1-SFX) | 9112775175 | @ProSoundEffects | Ambiente en bucle, ~56–64 s, 92 % (10+ votos) | Cama de ambiente del edificio en apagón |
| [Horror](https://create.roblox.com/store/asset/9039981149) | 9039981149 | APMOfficial | 2:07, drones oscuros, 95 % (40+ votos) | Cama musical de marketing; tensión |
| [Scary Atmosphere](https://create.roblox.com/store/asset/1847064374/Scary-Atmosphere) | 1847064374 | APMOfficial | 1:56, género Drones | Alternativa de cama musical |
| [Steel Door 4 (SFX)](https://create.roblox.com/store/asset/9119630175/Steel-Door-4-SFX) | 9119630175 | @ProSoundEffects | 2,1 s, puerta metálica con impactos | `DoorSlam`, puertas de servicio |
| [Door Long Squeaks 18 (SFX)](https://create.roblox.com/store/asset/9114145200/Door-Long-Squeaks-18-SFX) | 9114145200 | @ProSoundEffects | 2,9 s, chirrido, cerrojo y pestillo | `DoorOpen` / `WoodCreak` de puertas viejas |
| [Metal Creak Twisting Apart Cracking Breaks 5 (SFX)](https://create.roblox.com/store/asset/9116554136/Metal-Creak-Twisting-Apart-Cracking-Breaks-5-SFX) | 9116554136 | @ProSoundEffects | 13 s | Fenómeno inexplicable lejano; colapso |
| [Electricity Static 22 (SFX)](https://create.roblox.com/store/asset/9114247505/Electricity-Static-22-SFX) | 9114247505 | @ProSoundEffects | Duración sin confirmar | Parpadeo eléctrico de apagones |
| [Static Rough 3 (SFX)](https://create.roblox.com/store/asset/9119588836/Static-Rough-3-SFX) | 9119588836 | @ProSoundEffects | 1,2 s, interferencia áspera | Radio y CCTV (juego y marketing V4) |
| [Toggle Switch Metal Industrial Equipment 76 (SFX)](https://create.roblox.com/store/asset/9120099286/Toggle-Switch-Metal-Industrial-Equipment-76-SFX) | 9120099286 | @ProSoundEffects | Sin confirmar | `BreakerFlip` del puzle de corriente |
| [Oil Refinery Ambience 2 (SFX)](https://create.roblox.com/store/asset/9112839293/Oil-Refinery-Ambience-2-SFX) | 9112839293 | @ProSoundEffects | 32 s en bucle, zumbido de maquinaria | Sala de calderas |

> **Licencia:** Pro Sound Effects y APM son librerías profesionales que publican en el Store. Antes de usar cada pista, confirma en su ficha que está disponible y que se puede usar en experiencias. No lo he podido ver.

### Modelos (prioridad 2: pocos, oficiales, para probar)

| Asset | ID | Creador | Datos (según el buscador) | Uso propuesto |
|---|---|---|---|---|
| [House Props Pack - Duvall Drive](https://create.roblox.com/store/asset/10840642581/House-Props-Pack-Duvall-Drive) | 10840642581 | @Roblox (oficial) | Libros, antigüedades, marcos con arte intercambiable, PBR | Detalle de despacho, archivo y recepción: 5–10 piezas elegidas, no el pack |
| [House Furniture Pack - Duvall Drive](https://create.roblox.com/store/asset/10847897579/House-Furniture-Pack-Duvall-Drive) | 10847897579 | @Roblox (oficial) | Muebles, lámparas, alfombras; SurfaceAppearance (PBR) | Muebles de despacho antiguo: solo si encajan con la luz de Ashgrove |
| [Old CRT TV Mesh PBR](https://create.roblox.com/store/asset/10904527778/Old-CRT-TV-Mesh-PBR) | 10904527778 | Sin confirmar | Malla PBR (por el nombre) | Sala de cintas, y marketing V4 (CCTV) |
| [Hospital bed](https://create.roblox.com/store/asset/4750431468/Hospital-bed) | 4750431468 | Sin confirmar | Modelo; 100 % (10+ votos) | Enfermería, si existe la sala; probar antes de nada |

### Herramientas (prioridad 3)

| Asset | ID | Datos (según el buscador) | Valoración |
|---|---|---|---|
| [PolyCounter](https://create.roblox.com/store/asset/730546757) | 730546757 | Cuenta polígonos y pinta un mapa de calor de lo que hay que optimizar | Útil, pero es un plugin de terceros: revisar permisos antes. Primero usar lo oficial: **Scene Analysis** y **MicroProfiler** de Studio, que dan triángulos y draw calls por pasada sin instalar nada |

---

## C. Tabla de decisiones

Leyenda: ✔ bien · ~ dudoso o sin verificar · ✘ mal · — no aplica.

### Audio y modelos candidatos

| Asset (ID) | Uso propuesto | Estado | Visual | Rendimiento | Seguridad | Compatibilidad | Coste | Justificación |
|---|---|---|---|---|---|---|---|---|
| Sonidos ProSoundEffects (9119630175, 9114145200, 9116554136, 9114247505, 9119588836, 9120099286, 9112839293, 9112775175) | Puertas, electricidad, ambiente | **Probar** (escucha) | — | ✔ | ✔ (el audio no lleva scripts) | ✔ (`AudioLibrary` acepta cualquier id) | Sin confirmar | Grabaciones profesionales; sustituyen muestras de Roblox procesadas |
| Buzzing Fluorescent Light (619993906) | Zumbido de tubos | **Probar** | — | ✔ | ✔ | ✔ | Sin confirmar | Encaja con el pasillo y con el Apagón 4 |
| Horror (9039981149), Scary Atmosphere (1847064374) | Música de marketing y tensión | **Probar** | — | ✔ | ✔ | ✔ | Sin confirmar | APM con licencia; mejor para los vídeos que para el juego, que ya tiene `MusicController` |
| House Props Pack – Duvall Drive (10840642581) | Props de detalle | **Probar → Adaptar** | ~ (estilo doméstico victoriano; cuidar que no parezca una casa) | ~ (pack grande: usar solo piezas sueltas) | ~ (oficial; contenido no auditado) | ~ (hay que ponerlas en `Props`/`MapBuilder`) | Sin confirmar | Oficial y PBR; riesgo bajo de puerta trasera |
| House Furniture Pack – Duvall Drive (10847897579) | Muebles de despacho | **Probar → Adaptar** | ~ | ~ | ~ | ~ | Sin confirmar | Igual; competiría con los muebles propios, así que solo para huecos concretos |
| Old CRT TV Mesh PBR (10904527778) | Sala de cintas y marketing | **Probar** | ~ | ~ (conteo sin ver) | ~ (creador sin confirmar) | ✔ | Sin confirmar | Pieza icónica de terror analógico |
| Hospital bed (4750431468) | Enfermería | **Probar** (baja prioridad) | ~ | ~ | ~ | ~ | Sin confirmar | Solo si la sala existe; puede no aportar |

### Descartados

| Asset (ID) | Uso propuesto | Estado | Visual | Rendimiento | Seguridad | Compatibilidad | Coste | Justificación |
|---|---|---|---|---|---|---|---|---|
| Fluorescent Hanging Office Light (5019834253) | Lámpara | **Descartar** (juego) | ~ | ✘ (5.555 vértices por lámpara × cientos de lámparas) | ~ | ✘ | — | El fixture procedural cuesta una fracción; para mejorar el tubo, malla propia en Blender |
| Hospital (8503376115), Hospital Map For Horror Games (9928982560), abandoned hospital (1457576454) | Mapa | **Descartar** | ~ | ✘ | ✘ (uno lista 88 scripts) | ✘ | — | Mapas completos: rompen la generación procedural y la identidad visual |
| Space Station Interior / Architecture Pack – Beyond the Dark (10981024261, 10980780693) | — | **Descartar** | ✘ (ciencia ficción) | ✘ (~550 y ~2.075 MeshParts) | ~ (47 y 58 scripts, aunque oficiales) | ✘ | — | Estilo incompatible. Sirve como referencia técnica de kits modulares en los docs de Beyond the Dark |
| Heavy Duty Metal Door (8467121449), Metal Double Door (10804117411), Classic door (9937899378), L4D Saferoom Door (13973866) | Puertas | **Descartar** | ~ | ~ | ✘ (llevan scripts) | ✘ (el juego tiene su propio sistema de puertas) | — | Scripts innecesarios; el nombre «L4D» es de otro juego |
| DOORS : Wall Lamp (11523297223), SCP Sounds/Ambience (4671887694), fnaf … footstep (8460402354) | — | **Descartar** | — | — | ~ | — | — | Llevan nombres de otros juegos. Después de §4 de FALLOS (silueta copiada) no conviene ningún parecido |
| Red Beacon Light (462993813) | Baliza | **Descartar** | ✘ | ~ | ~ | ✘ | — | El juego ya tiene balizas propias |
| Lockers (202875351, 783494723), filing cabinets (8467064810, 233658065, 2889480566) | Mobiliario | **Descartar** por ahora | ~ (IDs antiguos, sin datos técnicos) | ~ | ~ | ✘ | — | Los muebles propios existen; el fallo es de carga, no de diseño |
| Realistic Materials (MaterialVariant) (11000216412) | Materiales | **Descartar** (reserva) | ~ | ✔ | ✔ | ✘ | — | Sustituiría la piel propia de Ashgrove; solo como plan B si las texturas propias no pudieran subirse |
| Zombie Animations Pack (138660902491405), Zombie walk animation (836864234) | Entidades | **Descartar** | ✘ | — | ~ | ✘ | — | El Observer y el Mimic no son R15: se posan por código. Y el Observer «nunca se ve moverse» |
| Walk on concrete SFX (534864172), Horror ambient (324562370) | Audio | **Descartar** | — | — | — | — | — | El buscador los marca como no disponibles |

---

## D. Comparación con lo existente

- **Conservar todo el sistema actual:**
  - `MapBuilder`, `Props`, `MaterialLibrary`, `HallwayBuilder`, `ObserverRig`/Mimic y las mallas propias de Blender.
  - Son coherentes entre sí, procedurales y ya probados (validador de mapa, z-fighting, pruebas de Lune).
- **Lo que no rinde hoy no es el diseño, es la carga (§0).**
  - Antes de comparar ningún prop del Store con uno propio, hay que ver el propio **cargado**. Comparar un modelo gratuito con nuestras piezas de respaldo de plástico sería injusto y llevaría a la decisión equivocada.
- **Lo que sí se puede sustituir con ventaja:**
  - **Audio:** algunas muestras de Roblox procesadas (puertas, interruptores, electricidad) por grabaciones profesionales.
  - **Detalle:** añadir unos pocos props oficiales en sitios concretos, sin reemplazar.

---

## E. Pruebas realizadas

| Tipo | Hecho | Resultado |
|---|---|---|
| Investigación online | ✔ | Unas 20 búsquedas restringidas a `create.roblox.com`. IDs reales de la URL; resto de datos de los fragmentos del buscador |
| Abrir la ficha oficial | ✘ | La red del entorno bloquea `create.roblox.com` y `apis.roblox.com` |
| Inspección del código de los modelos | ✘ | Sin descarga posible. **Ningún modelo real auditado** |
| Inserción en Studio | ✘ | Sin acceso a Studio |
| Prueba visual en el juego | ✘ | Sin acceso a Studio |
| Herramienta de auditoría | ✔ | `tools/audit_asset.luau` y `tools/lib/asset_audit.luau`; test `tools/audit_asset_test.luau`: **17 comprobaciones, 0 fallos** |

Qué comprueba el test de la herramienta, con modelos sintéticos guardados y releídos como `.rbxm`:
- Un mueble limpio sale como «sin patrones».
- Una lámpara con puerta trasera (`require(<id>)`, `loadstring`, HTTP, texto en `\ddd`, identificadores `lIl1`, un `RemoteEvent` nuevo) sale **REJECT**.
- La copia sin scripts de esa lámpara conserva geometría y luz.
- Una puerta con un script corriente sale como «revisar».
- Lee también las propiedades `…Content` con las que Studio guarda hoy texturas y mallas. Sin eso, las dependencias se escaparían.

---

## F. Plan de integración

Ordenado por impacto, riesgo y esfuerzo.

| # | Cambio | Impacto | Riesgo | Esfuerzo |
|---|---|---|---|---|
| 0 | **Volver a subir los recursos propios** desde tu cuenta o la del grupo: mallas `assets/props/*.obj`, texturas y hojas de audio `assets/audio`. Pásame los IDs (FALLOS §0) | Muy alto: desaparece el «plástico» | Nulo | Medio |
| 1 | **Audio del Store:** escuchar los candidatos de §B. Para cada uno aprobado, cambiar su entrada en `AudioLibrary` (`id = "rbxassetid://…"`). Cambio de una línea, reversible por entrada | Alto | Bajo | Bajo |
| 2 | **Props oficiales Duvall:** insertarlos en un place vacío, auditarlos con la herramienta y elegir 5–10 piezas. Guardarlas sin scripts en `assets/store/` y añadirlas como variantes de `Props`, revisadas con `validate_map` y `zfight` | Medio | Medio | Medio |
| 3 | **CRT TV** para la sala de cintas y el vídeo V4 | Medio (marketing) | Bajo | Bajo |
| 4 | PolyCounter, solo si Scene Analysis no basta | Bajo | Bajo | Bajo |

**Mecanismo propuesto para los modelos aprobados** (no aplicado: aún no hay ninguno aprobado):
- Guardar la copia **sin scripts** en `assets/store/<Nombre>.rbxm`.
- Mapearla con Rojo a `ServerStorage.StoreAssets`.
- Clonarla desde `Props`.

Así cada asset queda en el repo, versionado, auditable con la herramienta y reversible borrando un archivo. No hay dependencias en tiempo de ejecución ni `InsertService`.

### Pasillo imposible

- **Recomendación: conservar `HallwayBuilder`.** Es modular (segmentos de 12 studs), procedural y **compartido con el marketing**: las escenas de campaña construyen la misma geometría. Un pasillo descargado crearía dos versiones incoherentes.
- **Qué mejorar:**
  - el **sonido**, con el zumbido de tubos 619993906 y la estática 9114247505 para los cortes;
  - si se quiere más fidelidad en tubo y puerta, **mallas propias** con el pipeline de Blender que ya existe;
  - **no** usar lámparas del Store: 5.555 vértices × 40 por pasillo.
- **Diferencias entre secciones:** ya existen (placas B-31/13-B, manchas, tubos muertos). Se pueden ampliar en `HallwayBuilder` sin assets externos.

### Marketing (aparte del juego)

- **Exclusivo de marketing:** las pistas de APM (9039981149, 1847064374) como cama musical de los vídeos. Se añaden en `MarketingConfig` o en el editor de vídeo, **no** en el juego.
- **Compartido con el juego si se aprueba en §F-3:** CRT TV y props Duvall.
- No añadir dependencias al juego solo para un vídeo.

---

## G. Acciones manuales pendientes (tuyas)

**1. Para cada modelo que quieras evaluar:**
1. Abre **un place vacío** en Studio (nunca el del juego).
2. Inserta el asset desde la Toolbox con su ID.
3. **No le des a Play.** Selecciónalo → clic derecho → *Save to File…* → `.rbxm`.
4. Audítalo:
   ```
   lune run tools/audit_asset.luau ruta/Modelo.rbxm informe.md --strip Modelo_sin_scripts.rbxm
   ```
   - Si el veredicto es `REJECT` (código 2), descártalo.
   - Si es `REVIEW`, revisa sus scripts en el informe. Para decoración, usa la copia sin scripts.
5. Mira escala, pivote y colisiones en Studio. Luego pruébalo en una ronda (F8 → Start round) con la luz real y en un apagón.

**2. Para el audio:** pega el ID en la Toolbox (Audio) y escúchalo en contexto. Pásame los que apruebes y los pongo en `AudioLibrary`.

**3. Lo prioritario:** subir los recursos propios (§F-0) y pasarme los IDs.

---

## H. Resultado final (priorizado)

1. **Sube los recursos propios** (mallas, texturas y audio desde tu cuenta). Es la mayor mejora visual posible y no cuesta ni un asset externo.
2. **Escucha y aprueba el audio de Pro Sound Effects/APM** de §B. Riesgo casi nulo, mejora inmediata del sonido de puertas, electricidad y ambiente.
3. **Prueba los dos packs oficiales Duvall Drive** con el auditor y toma solo 5–10 piezas.
4. **CRT TV** para la sala de cintas y el vídeo de CCTV.
5. **Nada más.** Ni mapas, ni puertas con scripts, ni lámparas pesadas, ni animaciones R15, ni nada con nombre de otro juego.

## Fuentes

Fichas del Creator Store citadas arriba (IDs en las URL) y documentación oficial:
- [The Mystery of Duvall Drive](https://create.roblox.com/docs/resources/the-mystery-of-duvall-drive)
- [Beyond the Dark](https://create.roblox.com/docs/resources/beyond-the-dark)
- [Scene Analysis](https://create.roblox.com/docs/performance-optimization/scene-analysis)
- [Assemble modular environments](https://create.roblox.com/docs/tutorials/use-case-tutorials/modeling/assemble-modular-environments)
- [MaterialVariant](https://create.roblox.com/docs/reference/engine/classes/MaterialVariant)
