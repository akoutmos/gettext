defmodule Mix.Tasks.Gettext.Extract do
  use Mix.Task
  @recursive true

  @shortdoc "Extracts translations from source code"

  @moduledoc """
  Extracts translations by recompiling the Elixir source code.

      mix gettext.extract [OPTIONS]

  Translations are extracted into POT (Portable Object Template) files (with a
  `.pot` extension). The location of these files is determined by the `:otp_app`
  and `:priv` options given by Gettext modules when they call `use Gettext`. One
  POT file is generated for each translation domain.

  If you would like to verify that your POT files are up to date with the
  current state of the codebase, you can provide the `--check-up-to-date`
  flag. Note that this validation will fail even when the same calls to gettext
  only change location in the codebase:

      mix gettext.extract --check-up-to-date

  It is possible to give the `--merge` option to perform merging
  for every Gettext backend updated during merge:

      mix gettext.extract --merge

  All other options passed to `gettext.extract` are forwarded to the
  `gettext.merge` task (`Mix.Tasks.Gettext.Merge`), which is called internally
  by this task. For example:

      mix gettext.extract --merge --no-fuzzy

  """

  @switches [merge: :boolean, check_up_to_date: :boolean]

  def run(args) do
    Application.ensure_all_started(:gettext)
    _ = Mix.Project.get!()
    mix_config = Mix.Project.config()
    {opts, _} = OptionParser.parse!(args, switches: @switches)
    pot_files = extract(mix_config[:app], mix_config[:gettext] || [])

    if opts[:check_up_to_date] do
      run_up_to_date_check(pot_files)
    else
      run_translation_extraction(pot_files, opts, args)
    end
  end

  defp run_translation_extraction(pot_files, opts, args) do
    for {path, contents} <- pot_files do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, contents)
      Mix.shell().info("Extracted #{Path.relative_to_cwd(path)}")
    end

    if opts[:merge] do
      run_merge(pot_files, args)
    end

    :ok
  end

  defp run_up_to_date_check(pot_files) do
    pot_files
    |> Enum.reduce([], fn {path, contents}, not_extracted_acc ->
      cond do
        not File.exists?(path) ->
          [path | not_extracted_acc]

        not file_contents_match?(path, contents) ->
          [path | not_extracted_acc]

        true ->
          not_extracted_acc
      end
    end)
    |> check!()
  end

  defp file_contents_match?(path, contents) do
    File.read!(path) == contents
  end

  defp check!([]), do: :ok

  defp check!(not_extracted) do
    Mix.raise("""
    mix gettext.extract failed due to --check-up-to-date.
    The following POT files were not extracted or are out of date:
    #{to_bullet_list(not_extracted)}
    """)
  end

  defp to_bullet_list(files) do
    Enum.map_join(files, "\n", &"  * #{&1 |> to_string() |> Path.relative_to_cwd()}")
  end

  defp extract(app, gettext_config) do
    Gettext.Extractor.enable()
    force_compile()
    Gettext.Extractor.pot_files(app, gettext_config)
  after
    Gettext.Extractor.disable()
  end

  defp force_compile do
    Enum.map(Mix.Tasks.Compile.Elixir.manifests(), &make_old_if_exists/1)

    # If "compile" was never called, the reenabling is a no-op and
    # "compile.elixir" is a no-op as well (because it wasn't reenabled after
    # running "compile"). If "compile" was already called, then running
    # "compile" is a no-op and running "compile.elixir" will work because we
    # manually reenabled it.
    Mix.Task.reenable("compile.elixir")
    Mix.Task.run("compile")
    Mix.Task.run("compile.elixir")
  end

  defp make_old_if_exists(path) do
    :file.change_time(path, {{2000, 1, 1}, {0, 0, 0}})
  end

  defp run_merge(pot_files, argv) do
    pot_files
    |> Enum.map(fn {path, _} -> Path.dirname(path) end)
    |> Enum.uniq()
    |> Task.async_stream(&Mix.Tasks.Gettext.Merge.run([&1 | argv]), ordered: false)
    |> Stream.run()
  end
end
