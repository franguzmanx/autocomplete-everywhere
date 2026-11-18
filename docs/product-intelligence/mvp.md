# Autocomplete Everywhere — Primera versión a validar

**Alcance vigente: controles y percepción AX conectados al motor. Biblioteca desactivada por decisión del usuario el 5 de septiembre; aprendizaje acotado de preferencias implementado y opt-in, con utilidad real aún no demostrada. La validación en superficies reales se registra por separado.** Revisión del 6 de septiembre de 2026. Este documento reúne el alcance y su evaluación; el diseño integral conserva las ideas posteriores.

## Un trabajo

Ayudar a responder un mensaje o post concreto desde el campo actual, usando la fuente correcta y la intención que expresa el borrador. El beneficio buscado es terminar con menos esfuerzo una respuesta correcta y útil.

## Lo indispensable

- Obtener la fuente actual y vincularla al campo y destino; conservar revisiones mientras se escribe. El texto junto al cursor por sí solo no cumple la promesa.
- Una sugerencia final inline; aceptar o descartar sin envío automático. Verificar foco, destino, geometría e inserción una sola vez. Respetar campos seguros y funciones del host.
- Activar con la cuenta y permisos que la implementación real necesita; sin perfil obligatorio. Pausar no reinicia el primer uso.
- Menú con estado, pausa temporal, activar/desactivar en la aplicación actual, Ajustes y Salir. Ajustes reúne ayuda automática o a pedido y aplicaciones habilitadas, además del acceso/atajo necesario. Ritmo Quick/Balanced/Deliberate y visibilidad Subtle/Clear; sin selector de longitud.

## Control justo y necesario

- **Cuándo:** pausar 15 minutos, 30 minutos, una hora o hasta mañana a las 09:00 locales; sin pausa indefinida. Mostrar la hora de regreso y permitir reanudar antes. Una pausa temporal termina sola y conserva las exclusiones por aplicación. Usar una fecha de vencimiento, también al despertar o reiniciar; no reiniciar el plazo. Al volver, esperar una nueva oportunidad de escritura y obtener contexto vigente.
- **Dónde:** interruptor de la aplicación actual en el menú y lista de aplicaciones en Ajustes. La exclusión persiste y detiene tanto la captura como las sugerencias en esa aplicación, incluida la ayuda a pedido. Invalidar solicitudes en curso y descartar su contexto al desactivar; no dejar datos previos de esa app disponibles para otras tareas. Una exclusión de navegador abarca todos sus sitios; reglas por sitio quedan fuera de esta versión.
- **Cómo aparece:** ayuda automática o a pedido. Una pausa o exclusión tiene prioridad; pedir ayuda no la anula silenciosamente.

Estos controles responden a interrupciones y límites de uso. No requieren configurar personalidad ni aprender parámetros técnicos. La selección por aplicación es una preferencia explícita del usuario, no una ruta de interpretación distinta ni un clasificador semántico por app. La app lista las aplicaciones abiertas y conserva los identificadores con preferencias guardadas. Las preferencias viven en `preferences.json` local, separado de las credenciales. El modo inicial es automático; la captura sigue requiriendo cuenta y permisos. El menú y Ajustes cambian la misma configuración. El atajo a pedido es ⌘⇧Espacio; si otro proceso lo ocupa, Autocomplete Everywhere informa el conflicto. La maqueta mantiene aplicaciones de ejemplo y no representa el inventario real.

## Contexto e inteligencia implementados

Accessibility aporta fuentes de texto de solo lectura y campos relacionados junto con el borrador. Las fuentes incluyen identidad física, contenedor y relación estructural; compartir un contenedor no demuestra que sea el mensaje respondido. El helper conserva esta evidencia mientras se escribe y liga toda revisión del contexto a cancelación, presentación e inserción. Solo se admiten fuentes cuya visibilidad pueda verificarse dentro de ventana y áreas de scroll. No se archivan pantallas ni conversaciones.

La Biblioteca está desactivada para este MVP: no aparece en la navegación, no se carga y no aporta candidatos al motor. Sus archivos existentes se conservan. La implementación de referencias, recuerdos y estilo explícitos queda diferida; no debe contarse como una capacidad activa ni como aprendizaje automático.

Una generación final de Gemini a través de AI Gateway recibe borrador, contexto actual y candidatos admisibles. Se eliminó la inyección del antiguo perfil personal/empresa sin ámbito y su endpoint remoto. El modelo decide qué ayuda está fundamentada; el código valida formato, límites y vigencia. Texto de terceros, recuerdos, preferencias y hechos de referencia mantienen autoridades distintas. Un campo vacío más recuerdos incidentales no autoriza inventar una opinión.

## Capacidades que no están construidas

OCR/capturas visuales, interpretación de diagramas, historial fuera de pantalla, conectores, memoria factual automática y cobertura universal de apps. El aprendizaje de preferencias está implementado, apagado hasta que el usuario lo habilita: usa correcciones verificadas a texto aceptado, extracción de estilo en segundo plano y almacenamiento cifrado por cuenta. No aprende hechos ni interpreta una aceptación aislada como una preferencia. Su utilidad en uso real sigue pendiente de validación; ver el [registro MVP](./mvp-execution.md). Las observaciones de texto son temporales y se vinculan al campo original. El modo de captura no reconstruye una identidad de destinatario que el host no exponga. El ritmo de aparición y la visibilidad tienen controles simples; la extensión sigue siendo una decisión contextual del modelo.

## Qué no vamos a reinventar

Usar SwiftUI/AppKit para la ventana, Swift para captura e inserción y Electron como servicio y menú, Gemini 3.5 Flash-Lite vía AI Gateway y la salida final. El usuario seleccionó este motor tras el benchmark de escritura del 15 de septiembre de 2026. El modelo interpreta; el código conserva límites, procedencia, vigencia y autoridad de inserción.

Una pausa menor no demuestra rapidez útil. Los ritmos de aparición usan 150/300/700 ms; no son una promesa de latencia total. Medir tiempo hasta sugerencia útil antes de añadir llamadas o cachés.

## Prueba y decisión

1. **Percepción primero.** En una superficie de uso real, identificar mensaje y destino. Cambiar hilo, destinatario, tema o versión, incluyendo el fallo de contaminación observado. No avanzar a uso cotidiano si mezcla fuentes o no sabe a qué responde. El éxito en una superficie no demuestra cobertura universal.
2. **Valor contextual.** Comparar el flujo habitual con ayuda que usa la fuente observada y el borrador. Un control con borrador solo permite comprobar cuánto aporta la fuente. Incluir revisión y correcciones en el esfuerzo total.
3. **Oportunidad.** Comparar esa misma ayuda invocada y automática, con igual modelo, fuentes y salida; alternar orden sobre tareas equivalentes. Son condiciones de una evaluación, no productos distintos.

Registrar tiempo hasta texto correcto y utilizable, acciones, correcciones, interrupciones, abandonos, silencios y fallos. No ocultar intentos fallidos al resumir tiempos de éxito. Si la automática ahorra trabajo neto sin aumentar errores o vigilancia, priorizarla. Si interrumpe más de lo que ahorra, ajustar oportunidad o priorizar invocación. Si ninguna ayuda supera el flujo habitual, revisar la tarea o descartar la apuesta.

Si se reactiva la biblioteca, su utilidad se deberá probar con fuentes repetidas, ámbitos cruzados, correcciones y borrado. Su código existente no demuestra una capacidad activa ni recuperación semántica universal. El atlas sigue guiando los casos, incluidos casos negativos; no hay un porcentaje mínimo inventado ni una promesa de cobertura total.

## Evidencia y límites

El [registro de implementación](./intelligence-implementation.md) enumera contratos, revisiones y verificación. Los controles, captura, contexto reciente temporal, API y salida nativa están conectados. La biblioteca permanece desactivada. Una app firmada, pruebas de código y revisiones independientes no demuestran comprensión de todos los posts ni rapidez percibida. La matriz de casos sigue guiando las comprobaciones; las limitaciones de las fuentes se registran explícitamente.

## Interfaz nativa — 5 de septiembre de 2026

La ventana usa NSSplitViewController con material nativo en la barra lateral, formularios agrupados, SF Symbols y controles nativos. General tiene tres grupos: Suggestions (estado, pausa y práctica), Keyboard shortcut (atajo editable) y System (idioma y permisos). Writing separa comportamiento y apariencia con vista previa, y guarda sus cambios juntos mediante Save o ⌘S. El atajo se graba, se valida, persiste y aparece actualizado en el menú y la ayuda. Applications controla exclusiones. Library está oculta y desactivada. Account queda al pie de la barra lateral. Inglés por defecto, español seleccionable; el idioma de las sugerencias sigue la escritura.

Las explicaciones secundarias se abren en tooltips nativos al pasar el cursor por ⓘ, con ayuda equivalente para VoiceOver. Los errores, permisos pendientes y vencimientos relevantes permanecen visibles. La cabecera respeta las columnas nativas; no se fuerza una barra uniforme que desplace el título sobre la navegación.

La ventana no recibe credenciales y usa un pipe privado validado con el servicio. Los cambios de cuenta limpian borradores de biblioteca; cada cuenta mantiene almacenamiento cifrado separado. Se conserva la identidad interna de cifrado de Electron para poder leer los datos existentes sin moverlos.
