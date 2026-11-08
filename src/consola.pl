/*  Sherlog: entrada y salida por la terminal para el jugador humano.

    Este módulo solo sabe de cartas (juego.pl): no conoce a los jugadores
    ni el bucle de la partida. Así jugador.pl puede usarlo para el tipo
    humano sin crear un ciclo entre módulos.

        juego.pl  <-  consola.pl  <-  jugador.pl

    Todo lo que lee lo lee del flujo de entrada actual y todo lo que
    escribe va al flujo de salida actual. Los tests los sustituyen por
    flujos de texto, y no hace falta teclado.

    El humano solo ve lo que le permite su vista (mano, eliminados e
    historial público) y los eventos que le entrega el protocolo.
*/

:- module(consola,
          [ lista_de_nombres/2,
            mostrar_mano/1,
            mostrar_historial/2,
            mostrar_evento/2,
            mostrar_fin/2,
            pedir_opcion/3,
            elegir_de_lista/3,
            preguntar_accion/3,
            preguntar_carta/3
          ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(readutil)).
:- use_module(juego, [carta/2, nombre/2]).

%   ---------------------------------------------------------------------
%   Texto

%!  lista_de_nombres(+Cartas, -Texto) is det.
%
%   Los nombres de las cartas en una frase: "A, B y C".

lista_de_nombres(Cartas, Texto) :-
    maplist(nombre, Cartas, Nombres),
    unir_con_y(Nombres, Texto).

unir_con_y(Nombres, Texto) :-
    (   Nombres = []
    ->  Texto = ''
    ;   Nombres = [Uno]
    ->  Texto = Uno
    ;   append(Principio, [Ultimo], Nombres)
    ->  atomic_list_concat(Principio, ', ', Inicio),
        format(atom(Texto), "~w y ~w", [Inicio, Ultimo])
    ).

% Cómo se llama a un jugador: "tú" para el que juega con la consola.
jugador_texto(Yo, Yo, 'tú') :- !.
jugador_texto(_, Id, Texto) :- format(atom(Texto), "el jugador ~w", [Id]).

%   ---------------------------------------------------------------------
%   Mostrar

%!  mostrar_mano(+Mano) is det.

mostrar_mano(Mano) :-
    findall(C, ( carta(_, C), memberchk(C, Mano) ), EnOrden),
    lista_de_nombres(EnOrden, Texto),
    format("Tus cartas: ~w.~n", [Texto]).

%!  mostrar_historial(+Yo, +Historial) is det.

mostrar_historial(_, []) :-
    !,
    format("~n-- Historial --~n  (todavía no ha pasado nada)~n").
mostrar_historial(Yo, Historial) :-
    format("~n-- Historial --~n"),
    forall(member(Evento, Historial), mostrar_evento(Yo, Evento)),
    format("--~n").

%!  mostrar_evento(+Yo, +Evento) is det.
%
%   Cuenta en español un evento del protocolo, desde el punto de vista
%   del jugador Yo.

mostrar_evento(Yo, sugerencia(Quien, Cartas, Respuestas)) :-
    !,
    lista_de_nombres(Cartas, Texto),
    (   Quien == Yo
    ->  format("Sugieres: ~w.~n", [Texto])
    ;   format("El jugador ~w sugiere: ~w.~n", [Quien, Texto])
    ),
    mostrar_respuestas(Yo, Respuestas).
mostrar_evento(Yo, acusacion(Quien, Cartas, Resultado)) :-
    !,
    lista_de_nombres(Cartas, Texto),
    (   Quien == Yo
    ->  format("Acusas a: ~w.~n", [Texto]),
        (   Resultado == acierta
        ->  format("  ¡Has acertado!~n")
        ;   format("  Te has equivocado y quedas eliminado.~n")
        )
    ;   format("El jugador ~w acusa a: ~w.~n", [Quien, Texto]),
        (   Resultado == acierta
        ->  format("  ¡Ha acertado!~n")
        ;   format("  Se ha equivocado y queda eliminado.~n")
        )
    ).
mostrar_evento(_, carta_vista(Refutador, Carta)) :-
    !,
    nombre(Carta, Nombre),
    format("  El jugador ~w te enseña: ~w.~n", [Refutador, Nombre]).
mostrar_evento(_, Evento) :-
    format("(~q)~n", [Evento]).

mostrar_respuestas(_, []) :-
    !,
    format("  Nadie tenía que responder.~n").
mostrar_respuestas(Yo, Respuestas) :-
    forall(member(Respuesta, Respuestas), mostrar_respuesta(Yo, Respuesta)),
    (   memberchk(refuto(_), Respuestas)
    ->  true
    ;   format("  Nadie pudo refutar.~n")
    ).

mostrar_respuesta(Yo, no_pudo(J)) :-
    (   J == Yo
    ->  format("  No tenías ninguna de esas cartas.~n")
    ;   format("  El jugador ~w no pudo refutar.~n", [J])
    ).
mostrar_respuesta(Yo, refuto(J)) :-
    (   J == Yo
    ->  format("  Refutaste tú.~n")
    ;   format("  El jugador ~w refutó.~n", [J])
    ).

%!  mostrar_fin(+Yo, +Resultado) is det.
%
%   El final de la partida: quién gana (o que has perdido), por qué y
%   cuál era el sobre.

mostrar_fin(Yo, fin(Ganador, Motivo, partida(sobre(S, A, L), _, _, Eliminados, _), _)) :-
    format("~n== Fin de la partida ==~n"),
    mostrar_motivo(Yo, Ganador, Motivo),
    lista_de_nombres([S, A, L], Sobre),
    format("El sobre era: ~w.~n", [Sobre]),
    (   Motivo = eliminado(_)
    ->  true
    ;   Eliminados == []
    ->  true
    ;   format("Eliminados, por orden: ~w.~n", [Eliminados])
    ).

mostrar_motivo(Yo, Ganador, acierta) :-
    jugador_texto(Yo, Ganador, Quien),
    format("Gana ~w: acusó correctamente.~n", [Quien]).
mostrar_motivo(Yo, Ganador, ultimo) :-
    jugador_texto(Yo, Ganador, Quien),
    format("Gana ~w: es el único jugador que queda sin eliminar.~n", [Quien]).
mostrar_motivo(Yo, _, eliminado(Id)) :-
    (   Id == Yo
    ->  format("Has perdido: te has equivocado al acusar y quedas eliminado, así que la partida termina aquí.~n")
    ;   format("El jugador ~w queda eliminado y la partida termina.~n", [Id])
    ).

%   ---------------------------------------------------------------------
%   Preguntar

% Lee una línea de la entrada, sin espacios de más. Si la entrada se
% acaba es un error: de lo contrario las preguntas se repetirían para siempre.
leer_linea(Linea) :-
    current_input(Entrada),
    read_line_to_string(Entrada, Cruda),
    (   Cruda == end_of_file
    ->  throw(error(fin_de_la_entrada, _))
    ;   normalize_space(string(Linea), Cruda)
    ).

%!  pedir_opcion(+Min, +Max, -N) is det.
%
%   Pide un número entero entre Min y Max y repite la pregunta mientras
%   lo escrito no sea válido.

pedir_opcion(Min, Max, N) :-
    format("> "),
    flush_output,
    leer_linea(Linea),
    (   number_string(N0, Linea),
        integer(N0),
        between(Min, Max, N0)
    ->  N = N0
    ;   format("  Escribe un número entre ~w y ~w.~n", [Min, Max]),
        pedir_opcion(Min, Max, N)
    ).

%!  elegir_de_lista(+Titulo, +Opciones, -Valor) is det.
%
%   Muestra un menú numerado. Opciones es una lista Etiqueta-Valor.

elegir_de_lista(Titulo, Opciones, Valor) :-
    format("~w~n", [Titulo]),
    numerar_opciones(Opciones, 1),
    length(Opciones, N),
    pedir_opcion(1, N, Elegida),
    nth1(Elegida, Opciones, _-Valor).

numerar_opciones([], _).
numerar_opciones([Etiqueta-_|Resto], I) :-
    format("  ~w) ~w~n", [I, Etiqueta]),
    I1 is I + 1,
    numerar_opciones(Resto, I1).

%!  preguntar_accion(+Id, +Vista, -Accion) is det.
%
%   Le toca al jugador Id. Accion es sugerir(S, A, L) o acusar(S, A, L).
%   Antes de preguntar le recuerda su mano; puede ver el historial las
%   veces que quiera. Una acusación pide confirmación: si se equivoca,
%   queda eliminado.

preguntar_accion(Id, Vista, Accion) :-
    Vista = vista(Mano, _, Historial),
    format("~n== Tu turno ==~n"),
    mostrar_mano(Mano),
    elegir_de_lista("¿Qué quieres hacer?",
                    [ 'Sugerir (preguntar a los demás)'-sugerir,
                      'Acusar (decir cuál es el sobre)'-acusar,
                      'Ver el historial'-historial ],
                    Que),
    (   Que == historial
    ->  mostrar_historial(Id, Historial),
        preguntar_accion(Id, Vista, Accion)
    ;   elegir_tres_cartas(Mano, S, A, L),
        (   Que == sugerir
        ->  Accion = sugerir(S, A, L)
        ;   confirmar_acusacion(S, A, L)
        ->  Accion = acusar(S, A, L)
        ;   preguntar_accion(Id, Vista, Accion)
        )
    ).

elegir_tres_cartas(Mano, S, A, L) :-
    elegir_carta("¿Qué sospechoso?", sospechoso, Mano, S),
    elegir_carta("¿Qué arma?", arma, Mano, A),
    elegir_carta("¿Qué lugar?", lugar, Mano, L).

% Un menú con las cartas de un tipo, avisando de las que son tuyas.
elegir_carta(Titulo, Tipo, Mano, Carta) :-
    findall(Etiqueta-C,
            ( carta(Tipo, C), etiqueta_de_carta(Mano, C, Etiqueta) ),
            Opciones),
    elegir_de_lista(Titulo, Opciones, Carta).

etiqueta_de_carta(Mano, Carta, Etiqueta) :-
    nombre(Carta, Nombre),
    (   memberchk(Carta, Mano)
    ->  format(atom(Etiqueta), "~w (la tienes tú)", [Nombre])
    ;   Etiqueta = Nombre
    ).

confirmar_acusacion(S, A, L) :-
    lista_de_nombres([S, A, L], Texto),
    format("Vas a acusar a: ~w.~n", [Texto]),
    elegir_de_lista("Si te equivocas quedas eliminado. ¿Seguro?",
                    [ 'Sí, acusar'-si, 'No, volver'-no ],
                    si).

%!  preguntar_carta(+Sugerencia, +Candidatas, -Carta) is det.
%
%   Al jugador le toca refutar la Sugerencia = sugerencia(Quien, Cartas).
%   Candidatas son las cartas de la sugerencia que tiene. Si solo tiene
%   una no hay nada que elegir.

preguntar_carta(sugerencia(Quien, Cartas), Candidatas, Carta) :-
    lista_de_nombres(Cartas, Texto),
    format("~nEl jugador ~w sugiere: ~w.~n", [Quien, Texto]),
    (   Candidatas = [Unica]
    ->  nombre(Unica, Nombre),
        format("Tienes que refutar y solo puedes enseñar: ~w.~n", [Nombre]),
        Carta = Unica
    ;   findall(Nombre-C, ( member(C, Candidatas), nombre(C, Nombre) ), Opciones),
        elegir_de_lista("Tienes que refutar. ¿Qué carta enseñas?", Opciones, Carta)
    ).
