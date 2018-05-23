open! Import
open! Signal
open! Always

let%expect_test "guarded assignment width mistmatch" =
  require_does_raise [%here] (fun () ->
    let w = Variable.wire ~default:vdd in
    compile [ w <-- zero 2 ]);
  [%expect {|
    ("attempt to assign expression to [Always.variable] of different width"
     (guared_variable_width 1)
     (expression_width      2)
     (expression (
       const
       (width 2)
       (value 0b00)))) |}]

let reg_spec = Reg_spec.create () ~clk:clock ~clr:clear

module State = struct
  type t = int [@@deriving compare, sexp_of]
  let all = [ 1; 3; 5 ]
end

let%expect_test "[Reg.State_machine.create]" =
  let sm () = State_machine.create (module State) reg_spec ~e:enable in
  let bad_case (state : _ State_machine.t) = state.switch [ 1, []; 2, []; 6, [] ] in
  let bad_next (state : _ State_machine.t) = state.switch [ 1, [ state.set_next 4] ] in
  let incomplete ?default (state : _ State_machine.t) =
    state.switch ?default [ 1, []; 3, [] ] in
  let repeated   (state : _ State_machine.t) = state.switch [ 1, []; 1, [] ] in
  require_does_raise [%here] (fun () -> compile [ bad_case (sm ()) ]);
  [%expect {|
    ("[Always.State_machine.switch] got unknown states" (2 6)) |}];
  require_does_raise [%here] (fun () -> compile [ bad_next (sm ()) ]);
  [%expect {|
    ("[Always.State_machine.set_next] got unknown state" 4) |}];
  require_does_raise [%here] (fun () -> compile [ incomplete (sm ()) ]);
  [%expect {|
    ("[Always.State_machine.switch] without [~default] had unhandled states" (5)) |}];
  require_does_not_raise [%here] (fun () -> compile [ incomplete ~default:[] (sm ()) ]);
  [%expect {| |}];
  require_does_raise [%here] (fun () -> compile [ repeated (sm ()) ]);
  [%expect {|
    ("[Always.State_machine.switch] got repeated state" 1) |}]

let%expect_test "Statemachine.statmachine ~encoding" =
  let sm encoding = State_machine.create (module State) reg_spec ~encoding ~e:enable in
  let bad_case (state : _ State_machine.t) = state.switch [ 1, []; 2, []; 6, [] ] in
  let bad_next (state : _ State_machine.t) = state.switch [ 1, [ state.set_next 4] ] in
  let bad_test (state : _ State_machine.t) = when_ (state.is 4) [] in
  require_does_raise [%here] (fun () -> compile [ bad_case (sm Binary) ]);
  [%expect {|
    ("[Always.State_machine.switch] got unknown states" (2 6)) |}];
  require_does_raise [%here] (fun () -> compile [ bad_next (sm Binary) ]);
  [%expect {|
    ("[Always.State_machine.set_next] got unknown state" 4) |}];
  require_does_raise [%here] (fun () -> compile [ bad_test (sm Binary) ]);
  [%expect {|
    ("[Always.State_machine.is] got unknown state" 4) |}];
  require_does_raise [%here] (fun () -> compile [ bad_case (sm Onehot) ]);
  [%expect {|
    ("[Always.State_machine.switch] got unknown states" (2 6)) |}];
  require_does_raise [%here] (fun () -> compile [ bad_next (sm Onehot) ]);
  [%expect {|
    ("[Always.State_machine.set_next] got unknown state" 4) |}];
  require_does_raise [%here] (fun () -> compile [ bad_test (sm Onehot) ]);
  [%expect {|
    ("[Always.State_machine.is] got unknown state" 4) |}];
  require_does_raise [%here] (fun () -> compile [ bad_case (sm Gray) ]);
  [%expect {|
    ("[Always.State_machine.switch] got unknown states" (2 6)) |}];
  require_does_raise [%here] (fun () -> compile [ bad_next (sm Gray) ]);
  [%expect {|
    ("[Always.State_machine.set_next] got unknown state" 4) |}];
  require_does_raise [%here] (fun () -> compile [ bad_test (sm Gray) ]);
  [%expect {|
    ("[Always.State_machine.is] got unknown state" 4) |}]

let%expect_test "test statemachine encodings" =
  let module State = struct
    type t =
      | Idle
      | S5
      | S10
      | S15
      | Valid
    [@@deriving compare, enumerate, sexp_of, variants]
  end in
  let test ~encoding ~nickel ~dime =
    let state : State.t State_machine.t =
      State_machine.create (module State) reg_spec ~encoding ~e:vdd
    in
    let decoded =
      Array.init (List.length State.all) ~f:(fun _ -> Variable.wire ~default:gnd) in
    let enable_decoded state = decoded.(State.Variants.to_rank state) <--. 1 in
    compile [
      state.switch [
        Idle, [
          enable_decoded Idle;
          when_ nickel [ state.set_next S5 ];
          when_ dime [ state.set_next S10 ];
        ];
        S5, [
          enable_decoded S5;
          when_ nickel [ state.set_next S10 ];
          when_ dime [ state.set_next S15 ];
        ];
        S10, [
          enable_decoded S10;
          when_ nickel [ state.set_next S15 ];
          when_ dime [ state.set_next Valid ];
        ];
        S15, [
          enable_decoded S15;
          when_ nickel [ state.set_next Valid ];
          when_ dime [ state.set_next Valid ];
        ];
        Valid, [
          enable_decoded Valid;
          state.set_next Idle;
        ];
      ]
    ];
    let prefix = State_machine.Encoding.to_string encoding |> String.lowercase in
    let states = List.map State.all ~f:state.is |> List.rev
                 |> Signal.concat |> output (prefix ^ "_states") in
    let decoded = Array.to_list decoded |> List.rev |> List.map ~f:(fun d -> d.value)
                  |> Signal.concat |> output (prefix ^ "_decoded") in
    let current = state.current |> output (prefix ^ "_current") in
    states, decoded, current
  in
  let nickel, dime = input "nickel" 1, input "dime" 1 in
  let binary_states, binary_decoded, binary_cur = test ~encoding:Binary ~nickel ~dime in
  let onehot_states, onehot_decoded, onehot_cur = test ~encoding:Onehot ~nickel ~dime in
  let gray_states,   gray_decoded,   gray_cur   = test ~encoding:Gray   ~nickel ~dime in
  (* Once reset, the states all sequence the same and generated the same decoded output *)
  let ok =
    (* dont care during reset *)
    clear
    (* Same state sequences for all encodings *)
    |: (((binary_states ==: onehot_states)
         &: (binary_states ==: gray_states))
        (* The decoded output should match the derived state *)
        &: ((binary_states ==: binary_decoded)
            &: (onehot_states ==: onehot_decoded)
            &: (gray_states ==: gray_decoded)) )
    |> output "ok"
  in
  let run_sim ~verbose coins =
    let circuit =
      Circuit.create_exn ~name:"vending_machine"
        (if verbose
         then [ binary_states
              ; onehot_states
              ; gray_states
              ; binary_decoded
              ; onehot_decoded
              ; gray_decoded
              ; binary_cur
              ; onehot_cur
              ; gray_cur
              ; ok ]
         else [ ok ])
    in
    let sim = Cyclesim.create ~kind:Immutable circuit in
    let waves, sim = Waves.Waveform.create sim in
    let port_nickel, port_dime =
      Cyclesim.in_port sim "nickel", Cyclesim.in_port sim "dime" in
    let clr = Cyclesim.in_port sim "clear" in
    let cycle ~nickel ~dime =
      port_nickel := if nickel then Bits.vdd else Bits.gnd;
      port_dime   := if dime   then Bits.vdd else Bits.gnd;
      Cyclesim.cycle sim;
      port_nickel := Bits.gnd;
      port_dime   := Bits.gnd;
    in
    clr := Bits.vdd;
    Cyclesim.cycle sim;
    clr := Bits.gnd;
    List.iter coins ~f:(fun (nickel, dime) -> cycle ~nickel ~dime);
    Cyclesim.cycle sim;
    Cyclesim.cycle sim;
    Waves.Waveform.print ~display_height:(if verbose then 39 else 12) ~wave_width:1 waves;
  in
  let nickel, dime = (true, false), (false, true) in
  run_sim ~verbose:true [ nickel; nickel; nickel; nickel ];
  [%expect {|
    ┌Signals──┐┌Values───┐┌Waves─────────────────────────────────────────┐
    │clear    ││        1││────┐                                         │
    │         ││         ││    └───────────────────────                  │
    │clock    ││         ││┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─│
    │         ││         ││  └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ │
    │nickel   ││        0││    ┌───────────────┐                         │
    │         ││         ││────┘               └───────                  │
    │dime     ││        0││                                              │
    │         ││         ││────────────────────────────                  │
    │         ││         ││────────┬───┬───┬───┬───┬───                  │
    │binary_st││       01││ 01     │02 │04 │08 │10 │01                   │
    │         ││         ││────────┴───┴───┴───┴───┴───                  │
    │         ││         ││────┬───┬───┬───┬───┬───┬───                  │
    │onehot_st││       00││ 00 │01 │02 │04 │08 │10 │01                   │
    │         ││         ││────┴───┴───┴───┴───┴───┴───                  │
    │         ││         ││────────┬───┬───┬───┬───┬───                  │
    │gray_stat││       01││ 01     │02 │04 │08 │10 │01                   │
    │         ││         ││────────┴───┴───┴───┴───┴───                  │
    │         ││         ││────────┬───┬───┬───┬───┬───                  │
    │binary_de││       01││ 01     │02 │04 │08 │10 │01                   │
    │         ││         ││────────┴───┴───┴───┴───┴───                  │
    │         ││         ││────┬───┬───┬───┬───┬───┬───                  │
    │onehot_de││       00││ 00 │01 │02 │04 │08 │10 │01                   │
    │         ││         ││────┴───┴───┴───┴───┴───┴───                  │
    │         ││         ││────────┬───┬───┬───┬───┬───                  │
    │gray_deco││       01││ 01     │02 │04 │08 │10 │01                   │
    │         ││         ││────────┴───┴───┴───┴───┴───                  │
    │         ││         ││────────┬───┬───┬───┬───┬───                  │
    │binary_cu││        0││ 0      │1  │2  │3  │4  │0                    │
    │         ││         ││────────┴───┴───┴───┴───┴───                  │
    │         ││         ││────┬───┬───┬───┬───┬───┬───                  │
    │onehot_cu││       00││ 00 │01 │02 │04 │08 │10 │01                   │
    │         ││         ││────┴───┴───┴───┴───┴───┴───                  │
    │         ││         ││────────┬───┬───┬───┬───┬───                  │
    │gray_curr││        0││ 0      │1  │3  │2  │6  │0                    │
    │         ││         ││────────┴───┴───┴───┴───┴───                  │
    │ok       ││        1││────────────────────────────                  │
    │         ││         ││                                              │
    └─────────┘└─────────┘└──────────────────────────────────────────────┘ |}];
  run_sim ~verbose:false [ nickel; dime; nickel ];
  [%expect {|
    ┌Signals──┐┌Values───┐┌Waves─────────────────────────────────────────┐
    │clock    ││         ││┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─│
    │         ││         ││  └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ │
    │nickel   ││        0││    ┌───┐   ┌───┐                             │
    │         ││         ││────┘   └───┘   └───────                      │
    │dime     ││        0││        ┌───┐                                 │
    │         ││         ││────────┘   └───────────                      │
    │clear    ││        1││────┐                                         │
    │         ││         ││    └───────────────────                      │
    │ok       ││        1││────────────────────────                      │
    │         ││         ││                                              │
    └─────────┘└─────────┘└──────────────────────────────────────────────┘ |}];
  run_sim ~verbose:false [ dime; dime ];
  [%expect {|
    ┌Signals──┐┌Values───┐┌Waves─────────────────────────────────────────┐
    │clock    ││         ││┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─│
    │         ││         ││  └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ │
    │nickel   ││        0││                                              │
    │         ││         ││────────────────────                          │
    │dime     ││        0││    ┌───────┐                                 │
    │         ││         ││────┘       └───────                          │
    │clear    ││        1││────┐                                         │
    │         ││         ││    └───────────────                          │
    │ok       ││        1││────────────────────                          │
    │         ││         ││                                              │
    └─────────┘└─────────┘└──────────────────────────────────────────────┘ |}];
  run_sim ~verbose:false [ nickel; nickel; dime ];
  [%expect {|
    ┌Signals──┐┌Values───┐┌Waves─────────────────────────────────────────┐
    │clock    ││         ││┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─│
    │         ││         ││  └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ │
    │nickel   ││        0││    ┌───────┐                                 │
    │         ││         ││────┘       └───────────                      │
    │dime     ││        0││            ┌───┐                             │
    │         ││         ││────────────┘   └───────                      │
    │clear    ││        1││────┐                                         │
    │         ││         ││    └───────────────────                      │
    │ok       ││        1││────────────────────────                      │
    │         ││         ││                                              │
    └─────────┘└─────────┘└──────────────────────────────────────────────┘ |}]
;;
