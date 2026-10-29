defmodule TransportWeb.Components.ColorfulButtonTest do
  use ExUnit.Case, async: true

  # Test the classnames function directly by importing it
  import TransportWeb.Components.ColorfulButton, only: [classnames: 3]

  describe "classnames" do
    test "valid and not selected returns 'colorful valid'" do
      assert classnames(nil, false, false) == "colorful variant-valid"
    end

    test "invalid and not selected returns 'colorful error'" do
      assert classnames(:error, false, false) == "colorful variant-error"
    end

    test "invalid with variant warning includes 'variant-warning' class" do
      assert classnames(:warning, false, false) == "colorful variant-warning"
    end

    test "invalid with variant information includes 'information' class" do
      assert classnames(:information, false, false) == "colorful variant-information"
    end

    test "selected adds selected class" do
      assert classnames(:error, false, true) == "colorful variant-error selected"
    end

    test "striped adds striped class" do
      assert classnames(:error, true, false) == "colorful variant-error striped"
    end

    test "all classes can be combined" do
      assert classnames(:warning, true, true) == "colorful variant-warning striped selected"
    end
  end
end
