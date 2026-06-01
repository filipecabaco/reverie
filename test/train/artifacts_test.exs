defmodule Train.ArtifactsTest do
  use ExUnit.Case, async: true

  alias Train.Artifacts

  @tag :tmp_dir
  test "verify/1 passes when all required files exist", %{tmp_dir: dir} do
    write_required_files(dir)
    assert :ok = Artifacts.verify(dir)
  end

  @tag :tmp_dir
  test "verify/1 fails when adapter_model.safetensors is missing", %{tmp_dir: dir} do
    write_required_files(dir)
    File.rm!(Path.join(dir, "adapter_model.safetensors"))
    assert {:error, {:missing_files, missing}} = Artifacts.verify(dir)
    assert "adapter_model.safetensors" in missing
  end

  @tag :tmp_dir
  test "verify/1 fails when checksums.json is missing", %{tmp_dir: dir} do
    write_required_files(dir)
    File.rm!(Path.join(dir, "checksums.json"))
    assert {:error, {:missing_files, _}} = Artifacts.verify(dir)
  end

  test "verify/1 fails for non-existent path" do
    assert {:error, {:not_a_directory, _}} = Artifacts.verify("/no/such/path")
  end

  @tag :tmp_dir
  test "checksums/1 returns a map of filename to hex digest", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "adapter_config.json"), ~s({"r":16}))
    File.write!(Path.join(dir, "checksums.json"), ~s({}))

    sums = Artifacts.checksums(dir)
    assert Map.has_key?(sums, "adapter_config.json")
    assert String.match?(sums["adapter_config.json"], ~r/^[0-9a-f]{64}$/)
  end

  @tag :tmp_dir
  test "write_provenance/3 writes a JSON file with config fields", %{tmp_dir: dir} do
    config = %Train.Config{
      base_model: "facebook/opt-125m",
      dataset_path: dir,
      output_path: dir,
      seed: 42
    }

    Artifacts.write_provenance(dir, config, %{dataset_hash: "abc123"})

    path = Path.join(dir, "training_config.json")
    assert File.exists?(path)

    parsed = path |> File.read!() |> Jason.decode!()
    assert parsed["base_model"] == "facebook/opt-125m"
    assert parsed["seed"] == 42
    assert parsed["dataset_hash"] == "abc123"
  end

  defp write_required_files(dir) do
    File.write!(Path.join(dir, "adapter_config.json"), ~s({"r":16}))
    File.write!(Path.join(dir, "adapter_model.safetensors"), <<0, 1, 2, 3>>)
    File.write!(Path.join(dir, "checksums.json"), ~s({}))
  end
end
