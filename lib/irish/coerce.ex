defmodule Irish.Coerce do
  @moduledoc """
  Consistent type coercion for raw Baileys data.

  Baileys may deliver numeric fields as integers, strings, or floats depending
  on the Protobuf encoding path and JavaScript serialization. These helpers
  normalize incoming data so `from_raw/1` functions produce predictable types.
  """

  @doc "Coerce a value to boolean. Only `true` returns `true`."
  @spec bool(any()) :: boolean()
  def bool(v), do: v == true

  @doc "Coerce a value to integer. Accepts integers, numeric strings, and floats."
  @spec int(any()) :: integer() | nil
  def int(v) when is_integer(v), do: v
  def int(v) when is_float(v), do: trunc(v)

  def int(v) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> i
      :error -> nil
    end
  end

  def int(_), do: nil

  @doc "Coerce a value to a non-negative integer (e.g., counts, timestamps)."
  @spec non_neg_int(any()) :: non_neg_integer() | nil
  def non_neg_int(v) do
    case int(v) do
      i when is_integer(i) and i >= 0 -> i
      _ -> nil
    end
  end

  @doc "Coerce a value to string. Returns nil for nil/non-binary."
  @spec string(any()) :: String.t() | nil
  def string(v) when is_binary(v) and v != "", do: v
  def string(_), do: nil
end
