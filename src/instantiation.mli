(** Instantiation of sub-modules.

    For use with generated RTL when we want to reference some non-hardcaml modules. *)

open! Import

val create
  :  ?lib:string
  -> ?arch:string
  -> ?instance:string
  -> ?parameters:Parameter.t list
  -> unit
  -> name:string
  -> inputs:(string * Signal.t) list
  -> outputs:(string * int) list
  -> Signal.t Map.M(String).t

module With_interface (I : Interface.S) (O : Interface.S) : sig
  (** Instantiate an RTL design with the given input and output interface. *)
  val create
    :  ?lib:string
    -> ?arch:string
    -> ?instance:string
    -> ?parameters:Parameter.t list
    -> name:string
    -> Signal.t Interface.Create_fn(I)(O).t
end

val create_with_interface
  :  (module Interface.S_Of_signal with type Of_signal.t = 'i)
  -> (module Interface.S_Of_signal with type Of_signal.t = 'o)
  -> ?lib:string
  -> ?arch:string
  -> ?instance:string
  -> ?parameters:Parameter.t list
  -> name:string
  -> 'i
  -> 'o
