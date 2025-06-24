defmodule Transport.S3Test do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  test "bucket_name" do
    expected = "transport-data-gouv-fr-resource-history-test"
    assert expected == Transport.S3.bucket_name(:history)

    assert_raise KeyError, fn ->
      Transport.S3.bucket_name(:foo)
    end
  end

  describe "permanent_url" do
    @bucket_name Transport.S3.bucket_name(:history)
    test "no path" do
      assert "https://#{@bucket_name}.cellar-c2.services.clever-cloud.com" == Transport.S3.permanent_url(:history)
    end

    test "with path" do
      assert "https://#{@bucket_name}.cellar-c2.services.clever-cloud.com/foo/bar.zip" ==
               Transport.S3.permanent_url(:history, "foo/bar.zip")
    end
  end
end
