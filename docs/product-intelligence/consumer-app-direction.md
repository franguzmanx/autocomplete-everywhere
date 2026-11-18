# Autocomplete Everywhere — Dirección de la app de consumo

**Documento de trabajo · 15 de septiembre de 2026**

Recoge la conversación de producto y sus correcciones. Las decisiones confirmadas se distinguen de las propuestas por validar. Este documento no cambia el contrato técnico vigente ni acredita funciones implementadas, cobertura de aplicaciones o resultados comerciales.

## TL;DR

Autocomplete Everywhere ayuda a escribir dentro de las aplicaciones que una persona ya utiliza. La persona sigue con su trabajo habitual: recibe una continuación mientras escribe o selecciona un texto para mejorarlo con una acción concreta.

**Simplificar significa reducir el esfuerzo de entender y configurar el producto, conservando las funciones que aportan valor.** Se mantienen las acciones sobre texto y el control de ritmo. La hipótesis comercial es una suscripción de alrededor de 10 USD al mes; su viabilidad depende del coste personal real y de la utilidad de la ayuda.

## 1. Lo que ya acordamos

| Tema | Dirección confirmada en la conversación |
|---|---|
| Experiencia | Ayudar en el trabajo habitual sin exigir aprender a conversar con una IA. |
| Dos formas de uso | Completar mientras se escribe y mejorar texto seleccionado. |
| Acciones | Conservarlas: el usuario las utiliza mucho. Simplificar sus nombres y explorar propósitos como ventas. |
| Ritmo | Conservar el control y explicar sus opciones con palabras sencillas. |
| Interfaz y textos | Simplificar la organización, las explicaciones y las decisiones visibles. |
| Coste | Separar pruebas del uso personal antes de estimar cuánto cuesta servir a una persona. |
| Elección del modelo | Comparar calidad, velocidad y coste; no decidir únicamente por un ranking general. |

No están cerrados el conjunto exacto de acciones, la organización final de ajustes, el onboarding y las condiciones de la prueba gratuita.

## 2. Cómo explicamos el producto

### Analogía para probar

> Como tener la ayuda de ChatGPT justo donde escribes, sin copiar y pegar.

Es una analogía de uso, no una afirmación de integración con ChatGPT ni de equivalencia de capacidades.

Dos explicaciones concretas la acompañan:

- **Mientras escribes:** como el texto predictivo del móvil, pero para completar ideas.
- **Al seleccionar texto:** una acción para decirlo más claro, más corto o con un propósito concreto.

### Propuesta de mensaje principal

> **La ayuda de la IA, justo donde escribes.**
>
> Autocomplete Everywhere completa tus ideas y mejora tus textos en tus aplicaciones compatibles. Sin copiar y pegar.

La demostración debe mostrar una tarea reconocible: continuar un mensaje y mejorar otro. Evitar promesas de conocer todo el historial, funcionar en cualquier aplicación o hacer cualquier tarea.

**Nombre actual: Autocomplete Everywhere.** No se ha decidido otro nombre. El mensaje y la demostración deben explicar el beneficio sin depender de que el nombre lo haga por sí solo.

## 3. Las dos formas de uso

### Completa tus ideas

Escribir → ver una continuación → aceptar con Tab o seguir escribiendo para ignorarla.

Copy propuesto:

> Sigue escribiendo. Autocomplete Everywhere te sugiere cómo continuar.

La extensión depende de lo que ayuda a avanzar: puede ser una frase o un bloque en un campo multilínea. La persona revisa y decide. Aceptar una sugerencia no envía el mensaje.

### Dilo como quieres

Seleccionar texto → elegir una acción → revisar el resultado → aceptar el reemplazo o cancelar.

Copy propuesto:

> Selecciona un texto y elige qué mejorar.

Ambas formas de uso tienen que ser fáciles de descubrir. Las acciones no deben desaparecer detrás de una explicación centrada exclusivamente en autocompletado.

## 4. Acciones con nombres de resultados

**Propuesta de catálogo inicial; pendiente de validar.**

| Acción | Explicación visible |
|---|---|
| Mejorar | Hazlo más claro y natural. |
| Acortar | Di lo mismo con menos palabras. |
| Para ventas | Explica mejor el valor y propone un siguiente paso. |
| Para pedirle a la IA | Convierte tu idea en una petición clara. |
| Crear acción | Guarda una mejora que usas a menudo. |

Mostrar pocas favoritas y permitir añadir otras. Evitar que el usuario tenga que entender términos como «transformación», reglas de composición o parámetros del modelo.

Propuesta para crear una acción:

- **Nombre.**
- **Qué quieres mejorar.** Una explicación en lenguaje normal.
- **Ejemplo**, opcional.
- **Atajo**, opcional.

Las acciones preservan intención, hechos y condiciones. «Para ventas» no autoriza inventar descuentos, prestaciones, reuniones confirmadas ni resultados de clientes.

### Ventas con contexto: capacidad propuesta

El usuario quiere que una acción pueda aprovechar los últimos mensajes relevantes. Eso requiere suministrar contexto del hilo correcto a la transformación; cambiar el nombre de la acción no basta.

La transformación actual recibe selección, reglas, instrucciones, ejemplos y forma del campo. No recibe el hilo. Si se incorpora, usar únicamente evidencia disponible y vinculada a la conversación actual. Cuando falte, no fingir que se recuerda lo hablado.

Ejemplo ficticio:

- Cliente: «Me interesa, pero necesito saber si sirve para cinco personas».
- Selección: «Sí, podemos hablar».
- Mejora posible: «Podemos revisar cómo encajaría en vuestro equipo de cinco personas. ¿Coordinamos una llamada?».

El resultado reconoce la necesidad y propone un paso; no afirma una compatibilidad que aún no está establecida.

## 5. Ritmo y control

El control de ritmo se conserva. Propuesta de etiqueta:

> **¿Cuánto esperas antes de ver una sugerencia?**
>
> Poco · Normal · Un poco más

Explicación:

> Autocomplete Everywhere espera una pausa al escribir antes de preparar una sugerencia.

Validar estas palabras con la experiencia real: el control cambia la espera antes de solicitar ayuda, no garantiza el tiempo de respuesta del modelo. No presentar «instantáneo» como una promesa sin medirlo.

Mantener también ayuda automática o a pedido, pausa temporal, exclusiones por aplicación y atajos. Las exclusiones son límites de privacidad; una acción manual no debe saltárselos.

## 6. Organización propuesta

| Sección | Contenido |
|---|---|
| Escritura | Sugerencias automáticas, ritmo, apariencia y atajos. |
| Acciones | Favoritas, edición y creación de acciones. |
| Privacidad | Aplicaciones excluidas y explicación de qué datos se utilizan. |
| Cuenta | Cuenta, ayuda y gestión de suscripción cuando exista. |

El menú del Mac mantiene acceso rápido al estado, pausa, exclusión de la aplicación actual, ajustes y salir.

Los textos deben describir acciones y consecuencias. La elección del proveedor y del modelo corresponde al producto. Mantener controles de accesibilidad y recuperación de permisos aunque se reduzca el resto de la interfaz.

Biblioteca, conectores, paneles de productividad y configuración extensa de personalidad quedan fuera de esta propuesta inicial. La personalización existente es voluntaria; su lugar en la oferta sigue pendiente y no se presupone que mejore los resultados.

## 7. Primer uso propuesto

1. **Activa Autocomplete Everywhere.** Cuenta y permisos con explicación de su finalidad y del envío de fragmentos para generar ayuda.
2. **Completa una idea.** Escribir y aceptar una continuación real con Tab.
3. **Mejora un texto.** Seleccionar y probar una acción.
4. **Listo. Vuelve a lo que estabas haciendo.**

Permitir saltar la práctica y recuperarla después. Evitar cuestionarios obligatorios sobre profesión, personalidad o tono. Las explicaciones de privacidad y permisos deben seguir siendo claras.

## 8. Oferta y precio por validar

Hipótesis inicial: **10 USD por persona al mes**, una oferta fácil de entender. La prueba de siete días sin tarjeta y el lanzamiento sin plan anual son propuestas, no decisiones finales. No anunciar uso ilimitado antes de conocer la distribución del consumo y los límites necesarios.

La persona es el primer usuario; un equipo pequeño podría pagar varias cuentas del mismo producto. Facturación conjunta e invitaciones serían una ampliación posterior según demanda. No se presupone una plataforma empresarial separada.

El coste debe medirse por persona y función, separando pruebas automatizadas. Contar también generaciones canceladas o descartadas; aceptar texto no es la única actividad que cuesta dinero. El total de una organización durante tests no es una factura personal representativa.

Un escenario intensivo no establece un máximo. Un máximo de coste requiere límites efectivos de solicitudes y tokens. El presupuesto debe incluir infraestructura, soporte y cobro además de generación.

## 9. Cómo tomaremos la decisión del motor

La calidad útil se comprueba en continuaciones y mejoras reales: conservar hechos e intención, entender el contexto correcto, escribir con naturalidad y abstenerse solo cuando corresponde.

La velocidad se mide hasta la respuesta completa utilizable, con el proveedor y configuración concretos. El coste se mide sobre todo el trabajo facturado, incluido razonamiento, cancelaciones y caché según las condiciones del proveedor.

Decisión posterior al benchmark (15 de septiembre de 2026): usar Gemini 3.5 Flash-Lite con thinking bajo. Se usa a través de Vercel AI Gateway, con OIDC o AI_GATEWAY_API_KEY; la activación requiere desplegar el backend. No se añaden rutas de respaldo o selección de modelos en la interfaz. Cualquier cambio técnico tendrá su propia validación y actualización explícita del contrato actual.

**Optima queda a cargo del usuario.** El benchmark está en preparación en la plataforma; no hay resultados que incorporar todavía. El usuario pedirá ayuda cuando la necesite. No iniciar seguimiento, nuevas ejecuciones ni gastos por este documento.

## 10. Siguiente trabajo de producto

- Revisar este mensaje de producto y los nombres de las acciones.
- Dibujar la organización y las dos prácticas del primer uso.
- Validar que se entiendan el ritmo, las exclusiones y la revisión antes de aceptar.
- Cerrar la oferta después de separar el consumo personal del de pruebas.

Cada propuesta visual o funcional debe preservar las dos formas de uso acordadas. Esta dirección organiza el trabajo; no autoriza por sí sola una implementación, publicación o cambio de proveedor.

## Referencias del producto

- [Alcance y contratos vigentes](README.md).
- [MVP y límites de evidencia](mvp.md).
- [Ajustes actuales](native-settings-contract.md).
- [Transformaciones actuales](../architecture/transforms.md).

Fuente editorial: conversación de producto del 15 de septiembre de 2026. Los textos de interfaz son borradores y los ejemplos comerciales son ficticios.
