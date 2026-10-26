/*  Demo: la IA (jugador 1) deduce la solución sin haberla visto.

    Uso:  swipl src/demo.pl
*/

:- use_module(deduccion).

:- initialization(main, main).

main :-
    modelo([3, 2, 2], P),
    tengo(P, 1, [mostaza, cuchillo, cocina]),
    mostro(P, 2, escarlata),
    refuto(P, 3, [prado, pistola, salon]),
    no_refuto(P, 2, [blanco, cuerda, biblioteca]),
    no_refuto(P, 3, [blanco, cuerda, biblioteca]),
    probabilidades(P, Probs),
    writeln('Probabilidad de que cada carta esté en el sobre:'),
    forall(member(C-Pct, Probs), format("  ~w: ~1f %~n", [C, Pct])),
    (   solucion_segura(P, S)
    ->  format("~nLa IA acusa: ~w~n", [S])
    ;   writeln('Todavía no hay suficiente información para acusar.')
    ).
