# Cómo trabajo en este repo

Proyecto personal, una sola persona, **commits directos a `main`**. Este documento es mi flujo de trabajo para no perderme: qué hacer, en qué orden y cómo dejar rastro.

## Herramientas

| Herramienta | Para qué |
|---|---|
| [`PLAN.md`](PLAN.md) | El *qué* y el *por qué* de cada fase |
| **Milestones** (`F0` … `F4`) | Una por fase; cada fase es una semana, con fecha límite |
| **Issues** | Una por tarea "celular" (1–4 h, final claro) |
| **Tablero Scrumban** (GitHub Project) | El *ahora*: qué está listo, en curso y hecho |

## El tablero

```
Backlog → Listo → En curso → Probando → Hecho
```

| Columna | Significa | Límite |
|---|---|---|
| **Backlog** | Existe, pero aún no toca (incluye los `borrador`) | — |
| **Listo** | Detallada y sin dependencias pendientes: puedo empezarla ya | 5 |
| **En curso** | La estoy haciendo | **2** |
| **Probando** | El código está, falta comprobar el criterio de "hecho" | 2 |
| **Hecho** | Criterio comprobado y commit en `main` | — |

**Regla de oro (Scrumban):** si "En curso" está lleno, no empiezo nada nuevo: termino o devuelvo algo al Backlog.

## Ciclo de una tarea

1. **Elegir:** la de número más bajo en *Listo* (`F1·03` antes que `F1·04`).
2. **Moverla a *En curso*.**
3. **Trabajar** marcando las casillas de *Pasos* en el issue.
4. **Moverla a *Probando*** y comprobar el *Criterio de "hecho"*.
5. **Commit** con `Closes #N`: GitHub cierra el issue. Después la muevo a *Hecho*.
6. Si apareció algo nuevo: crear un issue (plantilla *Tarea*, *Bug* o *Idea*) en vez de meterlo en la tarea actual.

## Tamaño de las tareas

| Tamaño | Tiempo | |
|---|---|---|
| **S** | ≤ 1 h | |
| **M** | 1–3 h | |
| **L** | medio día | Si parece más grande, **dividirla** antes de empezar |

## Borradores

Las fases futuras tienen issues con la etiqueta **`borrador`**: tareas con objetivo y pasos orientativos, pendientes de revisar. Al empezar una fase:

1. Releer `PLAN.md` y ajustar lo que haya cambiado.
2. Revisar cada borrador (objetivo, pasos, criterio, tamaño).
3. Quitar la etiqueta `borrador` y moverlo a *Listo*.

## Commits

Formato [Conventional Commits](https://www.conventionalcommits.org/es/), igual que el título de los issues:

```
tipo(área): descripción corta en minúsculas

Detalle opcional de qué y por qué.

Closes #12
```

> ⚠️ GitHub solo entiende las palabras clave **en inglés**: `Closes #12`, `Fixes #12`, `Resolves #12`. "Cierra #12" **no** cierra el issue. Para mencionar sin cerrar: `Refs #12`.

**Tipos:** `feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `chore`, `design`.

**Áreas:** `juego`, `deduccion`, `ia`, `consola`, `web`, `explicacion`, `informe`.

Ejemplo: `feat(deduccion): generalizar el motor a N jugadores` + `Closes #5`.
