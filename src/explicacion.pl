/*  Sherlog: por qué la IA sabe lo que sabe.

    El motor de deduccion.pl (CLP(FD)) deduce bien, pero no sabe explicar:
    sus restricciones no guardan el porqué. Este módulo hace lo contrario:
    razona con pocas reglas, legibles, y cada vez que prueba algo guarda la
    PRUEBA, de la que sale el texto en español.

    Tiene tres partes:

        1. El registro (registro_inicial/3, registrar/4): lo que una IA ha
           visto, cada cosa con el turno en que ocurrió. Es de cada IA y
           privado: la carta que le enseñaron a ella no está en el
           historial público.

        2. Las reglas (regla/3): "si J no pudo refutar, J no tiene esas
           cartas", "si todas las demás de su tipo están descartadas, esta
           está en el sobre"... Son datos, no código: regla(Nombre, Cabeza,
           Cuerpo).

        3. El metaintérprete (prueba/3): resuelve una meta con esas reglas
           y los hechos del registro, y devuelve el árbol de la prueba.
           Después explicar/3 lo convierte en texto.

    Un metaintérprete es un intérprete de Prolog escrito en Prolog: en vez
    de dejar que Prolog resuelva la meta, la resolvemos nosotros, y por eso
    podemos ir apuntando qué regla y qué hecho se usó en cada paso.

    Árbol de la prueba:

        hecho(Obs)                      algo que se vio (una observación)
        por(Regla, Meta, Hijos)         Meta se cumple por la Regla, y los
                                        Hijos son las pruebas de su cuerpo

    Este módulo solo depende de juego.pl (las cartas y sus nombres). No
    usa CLP(FD): los tests comprueban que lo que prueba nunca contradice a
    deduccion.pl.

    Lo que NO sabe explicar: las deducciones que necesitan contar (por
    ejemplo "ya conozco las 5 cartas de J, así que no tiene ninguna más") o
    razonar sobre varias refutaciones a la vez. El motor las deduce y este
    módulo no. Ver tests/cobertura_explicacion.pl.
*/

:- module(explicacion,
          [ registro_inicial/3,
            registrar/4,
            prueba/3,
            explicar/3,
            explicar_carta/5,
            explicar_acusacion/4,
            explicar_cartas/4
          ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pairs)).
:- use_module(library(assoc)).
:- use_module(library(time)).
:- use_module(juego, [carta/2, nombre/2]).

% ---------------------------------------------------------------------------
% 1. El registro
% ---------------------------------------------------------------------------

%   registro(Turno, Obs): Turno es cuántos eventos públicos (sugerencias y
%   acusaciones) ha visto ya la IA, que es el número del turno en el que
%   se está; Obs, la lista de observaciones, la más reciente primero:
%
%       mano(J, Cartas)               la mano de J (la IA solo conoce la suya)
%       jugadores(N)                  hay N jugadores
%       cuenta(J, N)                  J tiene N cartas (se ve en la mesa)
%       enseno(T, J, Carta)           en el turno T, J me enseñó Carta
%       no_pudo(T, Q, J, Cartas)      en el turno T, Q sugirió Cartas y J no pudo
%       refuto(T, Q, J, Cartas)       en el turno T, J refutó la sugerencia de Q
%       fallo(T, Q, Cartas)           en el turno T, Q acusó mal a Cartas

%!  registro_inicial(+Yo, +Partida, -Registro) is det.
%
%   Lo que Yo sabe al empezar: su mano y cuántas cartas tiene cada uno.

registro_inicial(Yo, partida(_, Manos, _, _, _), registro(0, Obs)) :-
    memberchk(Yo-Mano, Manos),
    length(Manos, N),
    findall(cuenta(J, Cuantas),
            ( member(J-Cs, Manos), length(Cs, Cuantas) ),
            Cuentas),
    Obs = [mano(Yo, Mano), jugadores(N)|Cuentas].

%!  registrar(+Yo, +Evento, +Registro, -Registro1) is det.
%
%   Yo ve un Evento (los de jugador.pl) y lo apunta con el turno en que
%   ocurre. Lo que le pasa a Yo mismo no se apunta: ya lo sabe.

registrar(Yo, Evento, registro(T, Obs), registro(T1, Obs1)) :-
    (   Evento = sugerencia(Q, Cartas, Respuestas)
    ->  T1 is T + 1,
        findall(O, ( member(R, Respuestas), respuesta_obs(R, Yo, T1, Q, Cartas, O) ), Nuevas)
    ;   Evento = carta_vista(J, Carta)
    ->  T1 = T,                              % es del mismo turno que la sugerencia
        Nuevas = [enseno(T, J, Carta)]
    ;   Evento = acusacion(Q, Cartas, falla)
    ->  T1 is T + 1,
        Nuevas = [fallo(T1, Q, Cartas)]
    ;   Evento = acusacion(_, _, _)
    ->  T1 is T + 1,
        Nuevas = []
    ;   T1 = T,
        Nuevas = []
    ),
    append(Nuevas, Obs, Obs1).

respuesta_obs(no_pudo(J), Yo, T, Q, Cartas, no_pudo(T, Q, J, Cartas)) :- J \== Yo.
respuesta_obs(refuto(J),  Yo, T, Q, Cartas, refuto(T, Q, J, Cartas))  :- J \== Yo.

% ---------------------------------------------------------------------------
% 2. Las reglas
% ---------------------------------------------------------------------------

%   Las metas que se pueden probar:
%
%       tiene(J, C)         J tiene la carta C
%       no_tiene(J, C)      J no tiene la carta C
%       descartada(C)       C no está en el sobre
%       en_sobre(C)         C está en el sobre
%
%   El cuerpo de cada regla es una lista de metas. visto(Obs) busca una
%   observación en el registro; carta/2, member/2, select/3, findall/3,
%   numlist/3, \== y \+ memberchk/2 son de Prolog y se llaman directamente.

regla(en_mi_mano, tiene(J, C),
      [ visto(mano(J, Mano)), member(C, Mano) ]).
regla(me_la_enseno, tiene(J, C),
      [ visto(enseno(_, J, C)) ]).
regla(refuto_con_la_unica, tiene(J, C),
      [ visto(refuto(_, _, J, Cs)), select(C, Cs, [A, B]),
        no_tiene(J, A), no_tiene(J, B) ]).

regla(no_pudo_refutar, no_tiene(J, C),
      [ visto(no_pudo(_, _, J, Cs)), member(C, Cs) ]).
regla(otro_la_tiene, no_tiene(J, C),
      [ tiene(J2, C), J2 \== J ]).
regla(no_esta_en_su_mano, no_tiene(J, C),
      [ visto(mano(J, Mano)), \+ memberchk(C, Mano) ]).
regla(conozco_todas_sus_cartas, no_tiene(J, C),
      [ visto(cuenta(J, N)), conocidas(J, Cs), length(Cs, N), \+ memberchk(C, Cs) ]).

regla(alguien_la_tiene, descartada(C),
      [ tiene(_, C) ]).
regla(acusacion_fallida, descartada(C),
      [ visto(fallo(_, _, Cs)), select(C, Cs, [A, B]),
        en_sobre(A), en_sobre(B) ]).

regla(nadie_la_tiene, en_sobre(C),
      [ visto(jugadores(N)), numlist(1, N, Js), ninguno_la_tiene(Js, C) ]).
regla(la_unica_de_su_tipo, en_sobre(C),
      [ carta(Tipo, C),
        findall(O, ( carta(Tipo, O), O \== C ), Otras),
        todas_descartadas(Otras) ]).

% Auxiliares para recorrer listas (no dicen nada por sí mismos).
regla(lista_vacia, ninguno_la_tiene([], _), []).
regla(lista_sigue, ninguno_la_tiene([J|Js], C),
      [ no_tiene(J, C), ninguno_la_tiene(Js, C) ]).
regla(lista_vacia, todas_descartadas([]), []).
regla(lista_sigue, todas_descartadas([O|Os]),
      [ descartada(O), todas_descartadas(Os) ]).

% Las metas auxiliares no se muestran en la explicación.
auxiliar(ninguno_la_tiene(_, _)).
auxiliar(todas_descartadas(_)).

% Lo que se llama directamente, sin buscar regla.
de_prolog(carta(_, _)).
de_prolog(member(_, _)).
de_prolog(select(_, _, _)).
de_prolog(findall(_, _, _)).
de_prolog(numlist(_, _, _)).
de_prolog(length(_, _)).
de_prolog(_ \== _).
de_prolog(\+ memberchk(_, _)).

% ---------------------------------------------------------------------------
% 3. El metaintérprete
% ---------------------------------------------------------------------------

%!  prueba(+Registro, +Meta, -Arbol) is semidet.
%
%   Arbol es la prueba más corta de Meta con las reglas y lo que hay en
%   el Registro. Falla si no hay prueba (con las reglas de arriba y hasta
%   cierta profundidad). Las pruebas se buscan por profundidad creciente:
%   así sale la más corta y las reglas que se llaman unas a otras
%   (tiene/no_tiene) no se quedan dando vueltas.

prueba(registro(_, Obs), Meta, Arbol) :-
    empty_assoc(Vacia),
    nb_setval(explicacion_memoria, Vacia),
    profundidad_maxima(Max),
    (   between(1, Max, Prof),
        resolver(Meta, Obs, Prof, Arbol)
    ->  true
    ;   fail
    ).

profundidad_maxima(N) :-
    (   current_prolog_flag(sherlog_profundidad, N0) -> N = N0 ; N = 6 ).

% resolver(+Meta, +Obs, +Profundidad, -Arbol)
resolver(Meta, Obs, _, Arbol) :-
    Meta = visto(Observacion),
    !,
    member(Observacion, Obs),
    Arbol = hecho(Observacion).
resolver(Meta, _, _, de_prolog) :-
    de_prolog(Meta),
    !,
    call(Meta).
resolver(conocidas(J, Cs), Obs, Prof, por(sus_cartas_conocidas, conocidas(J, Cs), Pruebas)) :-
    % Todas las cartas de J que se pueden probar que tiene (con pruebas cortas).
    !,
    nonvar(J),
    Prof > 1,
    ProfCuenta is min(Prof - 1, 3),
    conocidas_de(J, ProfCuenta, Obs, Cs, Pruebas).
resolver(Meta, Obs, Prof, por(Nombre, Meta, Hijos)) :-
    Prof > 0,
    (   auxiliar(Meta) -> Prof1 = Prof ; Prof1 is Prof - 1 ),   % recorrer una lista no cuenta
    regla(Nombre, Meta, Cuerpo),
    resolver_cuerpo(Cuerpo, Obs, Prof1, Hijos).

% Calcular las cartas conocidas de J es lo más caro de la búsqueda y se
% pide muchas veces igual, así que se apunta (la memoria vale solo para un
% prueba/3: el registro no cambia durante la búsqueda).
conocidas_de(J, Prof, Obs, Cs, Pruebas) :-
    Clave = J-Prof,
    (   nb_current(explicacion_memoria, Memoria),
        get_assoc(Clave, Memoria, Guardado)
    ->  Guardado = Cs-Pruebas
    ;   findall(C-Arbol,
                ( carta(_, C), once(resolver(tiene(J, C), Obs, Prof, Arbol)) ),
                Pares),
        pairs_keys_values(Pares, Cs, Pruebas),
        (   nb_current(explicacion_memoria, M0) -> true ; empty_assoc(M0) ),
        put_assoc(Clave, M0, Cs-Pruebas, M1),
        nb_setval(explicacion_memoria, M1)
    ).

resolver_cuerpo([], _, _, []).
resolver_cuerpo([Meta|Metas], Obs, Prof, Hijos) :-
    resolver(Meta, Obs, Prof, Arbol),
    (   Arbol == de_prolog
    ->  Hijos = Hijos1
    ;   Hijos = [Arbol|Hijos1]
    ),
    resolver_cuerpo(Metas, Obs, Prof, Hijos1).

% ---------------------------------------------------------------------------
% 4. El texto
% ---------------------------------------------------------------------------

%   Contexto = ctx(Yo, Nombres): quién explica (habla en primera persona) y
%   el nombre de cada jugador, como lista J-Nombre. Sin nombre se dice
%   "el jugador J".

%!  explicar(+Contexto, +Arbol, -Texto) is det.
%
%   Texto es la prueba en español, con una línea por paso y sangría según
%   la profundidad; cita el turno de cada observación.

explicar(Ctx, Arbol, Texto) :-
    lineas(Arbol, Ctx, 0, Lineas),
    atomic_list_concat(Lineas, '\n', Atomo),
    atom_string(Atomo, Texto).

%!  explicar_carta(+Registro, +Contexto, +Estado, +Carta, -Texto) is semidet.
%
%   Estado es en_sobre o descartada. Texto explica por qué; falla si este
%   módulo no sabe probarlo.

explicar_carta(Registro, Ctx, Estado, Carta, Texto) :-
    meta_de_estado(Estado, Carta, Meta),
    prueba(Registro, Meta, Arbol),
    explicar(Ctx, Arbol, Texto).

meta_de_estado(en_sobre, C, en_sobre(C)).
meta_de_estado(descartada, C, descartada(C)).

%!  explicar_acusacion(+Registro, +Contexto, +Cartas, -Texto) is det.
%
%   Texto explica por qué cada una de las tres Cartas de la acusación
%   está en el sobre. Si no sabe probar alguna lo dice.

explicar_acusacion(Registro, Ctx, Cartas, Texto) :-
    explicar_cartas(Registro, Ctx, Cartas, Pares),
    pairs_values(Pares, Partes),
    atomic_list_concat(Partes, '\n\n', Atomo),
    atom_string(Atomo, Texto).

%!  explicar_cartas(+Registro, +Contexto, +Cartas, -Pares) is det.
%
%   Pares es una lista Carta-Texto: por qué cada carta está en el sobre.
%   Cada una tiene un límite de tiempo (2 s; el flag sherlog_limite_explicacion
%   lo cambia): una búsqueda que no encuentra prueba puede tardar mucho, y la
%   explicación nunca debe dejar colgada la partida.

explicar_cartas(Registro, Ctx, Cartas, Pares) :-
    findall(C-T, ( member(C, Cartas), explicar_una(Registro, Ctx, C, T) ), Pares).

limite_de_explicacion(L) :-
    (   current_prolog_flag(sherlog_limite_explicacion, L0) -> L = L0 ; L = 2.0 ).

explicar_una(Registro, Ctx, Carta, Parte) :-
    nombre_de_carta(Carta, N),
    limite_de_explicacion(Limite),
    catch(( call_with_time_limit(Limite, explicar_carta(Registro, Ctx, en_sobre, Carta, Texto))
          -> Resultado = texto(Texto)
          ;  Resultado = sin_prueba
          ),
          time_limit_exceeded,
          Resultado = tardo),
    (   Resultado = texto(T)
    ->  Parte = T
    ;   Resultado == tardo
    ->  format(atom(Parte), "No he podido explicar por qué ~w está en el sobre: tardaba demasiado.", [N])
    ;   format(atom(Parte), "No sé explicar por qué ~w está en el sobre.", [N])
    ).

% lineas(+Arbol, +Ctx, +Nivel, -Lineas)
lineas(hecho(_), _, _, []) :- !.
lineas(por(sus_cartas_conocidas, conocidas(J, Cs), Pruebas), Ctx, Nivel, Lineas) :-
    !,
    length(Cs, N), quien(J, Ctx, Q), nombres_de_cartas(Cs, Ns),
    format(atom(F), "~w tiene ~w cartas y ya conozco todas (~w), porque:", [Q, N, Ns]),
    sangrar(Nivel, F, Linea),
    Nivel1 is Nivel + 1,
    hijos_lineas(Pruebas, Ctx, Nivel1, Sub),
    Lineas = [Linea|Sub].
lineas(por(nadie_la_tiene, en_sobre(C), [hecho(jugadores(N))|Pruebas]), Ctx, Nivel, Lineas) :-
    !,
    nombre_de_carta(C, Nom),
    format(atom(F), "~w está en el sobre, porque ninguno de los ~w jugadores tiene esa carta:", [Nom, N]),
    sangrar(Nivel, F, Linea),
    Nivel1 is Nivel + 1,
    hijos_lineas(Pruebas, Ctx, Nivel1, Sub),
    Lineas = [Linea|Sub].
lineas(por(Nombre, Meta, Hijos), Ctx, Nivel, Lineas) :-
    (   auxiliar(Meta)
    ->  hijos_lineas(Hijos, Ctx, Nivel, Lineas)          % no se muestra: sus hijos suben
    ;   sin_porque(Nombre)
    ->  Hechos = Hijos,
        frase_regla(Nombre, Meta, Hechos, Ctx, Frase),
        sangrar(Nivel, Frase, Linea),
        Lineas = [Linea]
    ;   conclusion(Meta, Ctx, Frase),
        Nivel1 is Nivel + 1,
        hijos_lineas(Hijos, Ctx, Nivel1, Sub),
        (   Sub == []
        ->  sangrar(Nivel, Frase, Linea), Lineas = [Linea]
        ;   format(atom(F2), "~w, porque:", [Frase]),
            sangrar(Nivel, F2, Linea), Lineas = [Linea|Sub]
        )
    ).

hijos_lineas(Hijos, Ctx, Nivel, Lineas) :-
    foldl(juntar(Ctx, Nivel), Hijos, [], Rev),
    reverse(Rev, Lineas0),
    append(Lineas0, Lineas).

juntar(Ctx, Nivel, Hijo, Acc, [Ls|Acc]) :-
    (   Hijo = hecho(Obs)
    ->  frase_hecho(Obs, Ctx, F), sangrar(Nivel, F, L), Ls = [L]
    ;   lineas(Hijo, Ctx, Nivel, Ls)
    ).

sangrar(Nivel, Frase, Linea) :-
    Espacios is Nivel * 2,
    length(Cs, Espacios), maplist(=(0' ), Cs),
    atom_codes(Pre, Cs),
    capitalizar(Frase, Mayuscula),
    format(atom(Linea), "~w- ~w", [Pre, Mayuscula]).

capitalizar(Texto, Capitalizado) :-
    format(atom(A), "~w", [Texto]),
    sub_atom(A, 0, 1, _, Primera),
    sub_atom(A, 1, _, 0, Resto),
    upcase_atom(Primera, Mayuscula),
    atom_concat(Mayuscula, Resto, Capitalizado).

% Reglas cuya frase ya lo dice todo (su cuerpo son solo hechos).
sin_porque(en_mi_mano).
sin_porque(me_la_enseno).
sin_porque(no_pudo_refutar).
sin_porque(no_esta_en_su_mano).

frase_regla(en_mi_mano, tiene(_, C), _, _, F) :-
    nombre_de_carta(C, N),
    format(atom(F), "~w está en mi mano.", [N]).
frase_regla(me_la_enseno, tiene(J, C), [hecho(enseno(T, _, _))], Ctx, F) :-
    quien(J, Ctx, Q), nombre_de_carta(C, N),
    format(atom(F), "En el turno ~w, ~w me enseñó ~w.", [T, Q, N]).
frase_regla(no_pudo_refutar, no_tiene(J, C), [hecho(no_pudo(T, S, _, Cs))], Ctx, F) :-
    quien(J, Ctx, Q), sugirio(S, Ctx, Sug), nombre_de_carta(C, N), nombres_de_cartas(Cs, Ns),
    format(atom(F), "~w no tiene ~w: en el turno ~w, cuando ~w ~w, no pudo refutar.",
           [Q, N, T, Sug, Ns]).
frase_regla(no_esta_en_su_mano, no_tiene(J, C), _, ctx(Yo, _), F) :-
    J == Yo, !,
    nombre_de_carta(C, N),
    format(atom(F), "~w no está en mi mano.", [N]).
frase_regla(no_esta_en_su_mano, no_tiene(J, C), _, Ctx, F) :-
    quien(J, Ctx, Q), nombre_de_carta(C, N),
    format(atom(F), "~w no tiene ~w: no está en su mano.", [Q, N]).

% La frase de lo que se concluye en un paso.
conclusion(tiene(J, C), ctx(Yo, _), F) :-
    J == Yo, !,
    nombre_de_carta(C, N), format(atom(F), "Yo tengo ~w", [N]).
conclusion(no_tiene(J, C), ctx(Yo, _), F) :-
    J == Yo, !,
    nombre_de_carta(C, N), format(atom(F), "Yo no tengo ~w", [N]).
conclusion(tiene(J, C), Ctx, F) :-
    quien(J, Ctx, Q), nombre_de_carta(C, N), format(atom(F), "~w tiene ~w", [Q, N]).
conclusion(no_tiene(J, C), Ctx, F) :-
    quien(J, Ctx, Q), nombre_de_carta(C, N), format(atom(F), "~w no tiene ~w", [Q, N]).
conclusion(descartada(C), _, F) :-
    nombre_de_carta(C, N), format(atom(F), "~w no puede estar en el sobre", [N]).
conclusion(en_sobre(C), _, F) :-
    nombre_de_carta(C, N), format(atom(F), "~w está en el sobre", [N]).

% Las observaciones que cuelgan de una regla con "porque".
frase_hecho(refuto(T, S, J, Cs), Ctx, F) :-
    quien(J, Ctx, Q), de_quien(S, Ctx, Sug), nombres_de_cartas(Cs, Ns),
    format(atom(F), "En el turno ~w, ~w refutó la sugerencia ~w (~w).", [T, Q, Sug, Ns]).
frase_hecho(fallo(T, S, Cs), Ctx, F) :-
    quien(S, Ctx, Q), nombres_de_cartas(Cs, Ns),
    format(atom(F), "En el turno ~w, ~w acusó a ~w y falló.", [T, Q, Ns]).
frase_hecho(enseno(T, J, C), Ctx, F) :-
    quien(J, Ctx, Q), nombre_de_carta(C, N),
    format(atom(F), "En el turno ~w, ~w me enseñó ~w.", [T, Q, N]).
frase_hecho(no_pudo(T, S, J, Cs), Ctx, F) :-
    quien(J, Ctx, Q), de_quien(S, Ctx, Sug), nombres_de_cartas(Cs, Ns),
    format(atom(F), "En el turno ~w, ~w no pudo refutar la sugerencia ~w (~w).", [T, Q, Sug, Ns]).
frase_hecho(mano(_, _), _, "Está en mi mano.").
frase_hecho(cuenta(J, N), Ctx, F) :-
    quien(J, Ctx, Q),
    format(atom(F), "~w tiene ~w cartas (se ve en la mesa).", [Q, N]).
frase_hecho(Otro, _, F) :-
    \+ Otro = refuto(_, _, _, _), \+ Otro = fallo(_, _, _), \+ Otro = enseno(_, _, _),
    \+ Otro = no_pudo(_, _, _, _), \+ Otro = mano(_, _), \+ Otro = cuenta(_, _),
    format(atom(F), "~w", [Otro]).

% "yo sugerí Daga, Cocina, Piscina" / "Beto sugirió ..."
sugirio(S, ctx(Yo, Nombres), Texto) :-
    (   S == Yo -> Texto = 'yo sugerí'
    ;   quien(S, ctx(Yo, Nombres), Q), format(atom(Texto), "~w sugirió", [Q])
    ).

% "de mí" / "de Beto" (de la sugerencia)
de_quien(S, ctx(Yo, Nombres), Texto) :-
    (   S == Yo -> Texto = 'mía'
    ;   quien(S, ctx(Yo, Nombres), Q), format(atom(Texto), "de ~w", [Q])
    ).

quien(J, ctx(Yo, Nombres), Texto) :-
    (   J == Yo -> Texto = yo
    ;   memberchk(J-N, Nombres) -> Texto = N
    ;   format(atom(Texto), "el jugador ~w", [J])
    ).

nombre_de_carta(C, N) :- ( nombre(C, N0) -> N = N0 ; N = C ).

nombres_de_cartas(Cs, Texto) :-
    maplist(nombre_de_carta, Cs, Ns),
    atomic_list_concat(Ns, ', ', Texto).
