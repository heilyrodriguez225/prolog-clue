# IA difícil: experimentos de mejora (issue #32)

300 partidas por celda, partidas de 3 jugadores, los asientos rotan. El error típico es de unos ±3 puntos. Se reproduce con:

    SHERLOG_UMBRAL=0.4 swipl tests/torneo.pl 300 2026 12 /tmp/res media+media+dificil

Sin variables de entorno la difícil juega como antes.

## 1. Acusar con riesgo (umbral de probabilidad)

La difícil acusa cuando el sobre más repetido entre los mundos que mira tiene probabilidad >= umbral, en vez de esperar la certeza. Combinación `media+media+dificil`, victorias de la difícil (y % de veces que queda eliminada por acusar mal):

| Umbral | Semilla 2026 | Semilla 7 |
|---|---|---|
| ninguno (antes) | 48,0 % (0 %) | 44,0 % (0 %) |
| 0,9 | 48,0 % (0 %) | |
| 0,7 | 49,3 % (0,3 %) | |
| 0,5 | 53,3 % (7,3 %) | |
| **0,4** | **58,0 % (9,3 %)** | **55,3 % (10,7 %)** |
| 0,3 | 58,0 % (18,0 %) | 54,3 % (20,3 %) |
| 0,2 | 48,7 % (42,0 %) | |

Combinación `azar+media+dificil` (semilla 2026): sin umbral gana la difícil 42,0 %; con 0,4, 50,7 % (eliminada 8,3 %).

Conclusión: con 0,4 la difícil gana entre 8 y 11 puntos más en las tres pruebas (por encima del error). Con umbrales altos casi no cambia nada, porque a esas probabilidades el motor ya suele haber demostrado la solución; con 0,2 acusa tan mal que no compensa.

## 2. Resultados negativos

| Cambio | Difícil gana (media+media+dificil, semilla 2026) |
|---|---|
| Línea base (minimizar entropía, 200 muestras) | 48,0 % |
| Minimizar el número de sobres distintos que quedan | 38,7 % (peor) |
| Minimizar la probabilidad de fallar si hubiera que acusar | 49,0 % (igual) |
| 600 muestras (4x más tiempo por partida: 10,8 s frente a unos 4 s) | 49,3 % (igual) |
| 60 muestras | 50,7 % (igual) |

Elegir otra cosa que minimizar o mirar más mundos no ayuda. Lo que importa es cuándo acusa, no qué sugiere.

## 3. No probado

Contar exacto cuando quedan pocos mundos (ya se enumeran todos si son pocos) y tener en cuenta qué aprenden los rivales con cada sugerencia.
