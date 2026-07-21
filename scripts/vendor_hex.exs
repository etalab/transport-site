# Fetch locked Hex tarballs straight from hex.pm into vendor/hex/.
# Works on a pristine machine (e.g. CI): no local cache involved, each tarball is
# checksum-verified by Hex. Push vendor/hex/ to the SAE afterwards.
# Hex tarballs are platform-independent source, so the result matches prod.
# Git deps (rambo) and native artifacts (appsignal/explorer) are out of scope.
dest = "vendor/hex"
File.mkdir_p!(dest)

# with_diagnostics swallows Elixir 1.19's "quoted keyword" warnings on mix.lock
{{lock, _}, _} = Code.with_diagnostics(fn -> Code.eval_file("mix.lock") end)

# mix.lock's 8th tuple element is the outer checksum: sha256 of the .tar file.
sha_ok? = fn tar, sha ->
  File.exists?(tar) and Base.encode16(:crypto.hash(:sha256, File.read!(tar)), case: :lower) == sha
end

# A package fetches/compiles a native artifact at build (NOT inside the tarball,
# so vendoring the tarball alone is incomplete) if its deps graph pulls one of
# these, or it uses a bare Makefile that isn't the pure-Erlang rebar3 flavour.
native_markers = [:rustler, :rustler_precompiled, :elixir_make, :cc_precompiler, :zigler]

native? = fn t ->
  build_tools = elem(t, 4)
  deps = elem(t, 5)
  Enum.any?(deps, &(elem(&1, 0) in native_markers)) or
    (:make in build_tools and :rebar3 not in build_tools)
end

pkgs = lock |> Map.values() |> Enum.filter(&(elem(&1, 0) == :hex))

Enum.each(pkgs, fn t ->
  name = to_string(elem(t, 1))
  version = elem(t, 2)
  sha = elem(t, 7)
  tar = Path.join(dest, "#{name}-#{version}.tar")

  # Verify the sha whether the tarball is already present or freshly fetched.
  action =
    if sha_ok?.(tar, sha) do
      "skip"
    else
      {_, 0} = System.cmd("mix", ["hex.package", "fetch", name, version, "--output", dest])
      true = sha_ok?.(tar, sha)
      "fetched"
    end

  # Both branches confirm the sha, so the suffix is always accurate.
  IO.puts("#{action} #{name} #{version} — checksum verified")
end)

flagged = pkgs |> Enum.filter(native?) |> Enum.map(&"#{elem(&1, 1)} #{elem(&1, 2)}") |> Enum.sort()

unless flagged == [] do
  IO.puts("\n⚠️  vendoring likely INCOMPLETE — these build/download a native artifact")
  IO.puts("    that is NOT in the Hex tarball (vendor it separately, for the prod arch):")
  Enum.each(flagged, &IO.puts("    - #{&1}"))
end
