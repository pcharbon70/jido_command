defmodule JidoCommandTest do
  use ExUnit.Case
  doctest JidoCommand

  test "greets the world" do
    assert JidoCommand.hello() == :world
  end
end
