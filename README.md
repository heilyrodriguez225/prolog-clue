# Sherlog 🔍

Un juego de deducción al estilo Clue con oponentes de IA que razonan en Prolog.

Proyecto final de la asignatura **Programación Declarativa**.

## La idea

Cada partida reparte las cartas al azar entre los jugadores y deja tres en un sobre: un sospechoso, un arma y un lugar. Gana quien descubra primero qué hay en el sobre.

Los oponentes son una IA escrita en Prolog. Cada jugada (quién mostró una carta, quién no pudo refutar una sugerencia) se convierte en una **restricción lógica** y Prolog deduce solo qué cartas pueden estar en el sobre. No hay tablas de posibilidades programadas a mano: se describe **qué se sabe** y el motor de restricciones (CLP(FD)) saca las conclusiones.

## Estado

🚧 En desarrollo. Por ahora está el motor de deducción de la IA (`src/deduccion.pl`) con una demo.

## Requisitos

- [SWI-Prolog](https://www.swi-prolog.org/) 9 o superior

## Probar la demo

```bash
swipl src/demo.pl
```

Salida:

```
Probabilidad de que cada carta esté en el sobre:
  blanco: 100.0 %
  cuerda: 100.0 %
  biblioteca: 100.0 %

La IA acusa: [blanco,cuerda,biblioteca]
```

La IA dedujo la solución sin haber visto esas cartas, solo a partir de quién refutó y quién no.

## Plan

- [x] Motor de deducción con restricciones
- [ ] Partida completa en consola: turnos, sugerencias, refutaciones y acusación
- [ ] Niveles de IA: fácil (al azar), medio (deducción) y difícil (ganancia de información)
- [ ] Explicación de por qué la IA acusa (metaintérprete)
- [ ] Interfaz web con la libreta de detective de la IA
- [ ] Torneo entre niveles de IA

## Conceptos de programación declarativa

| Parte | Concepto |
|---|---|
| Reglas del juego y reparto | Hechos, reglas y restricciones |
| Conocimiento de la IA | Restricciones de dominio finito (CLP(FD)) |
| "No pudo refutar" | Negación |
| Probabilidad de cada carta | Backtracking y `findall` sobre los mundos posibles |
| Estrategia de la IA | Aritmética y ganancia de información |
| "¿Por qué acusó la IA?" | Metaprogramación (metaintérprete) |
