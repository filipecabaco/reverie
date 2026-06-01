defmodule Research.CoordinatorTest do
  use ExUnit.Case, async: true

  alias Corpus.Store
  alias Research.{Brief, Coordinator}

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    {:ok, conn} = Store.open(:elixir, dir)
    on_exit(fn -> Store.close(conn) end)
    %{conn: conn}
  end

  describe "save_brief/2" do
    test "persists a brief and returns it", %{conn: conn} do
      brief = sample_brief("b1", :draft)
      assert {:ok, ^brief} = Coordinator.save_brief(brief, conn: conn)
      assert {:ok, _} = Store.get_brief(conn, brief.id)
    end

    test "accepts {:ok, brief} tuple for pipeline chaining", %{conn: conn} do
      brief = sample_brief("b2", :draft)
      assert {:ok, _} = Coordinator.save_brief({:ok, brief}, conn: conn)
    end
  end

  describe "verified_brief_for/3" do
    test "returns a usable brief when one exists for the topic", %{conn: conn} do
      brief = %Brief{sample_brief("b1", :usable_for_generation) | topic: "GenServer"}
      Store.save_brief(conn, brief)

      assert {:ok, found} =
               Coordinator.verified_brief_for("GenServer", :verified_only,
                 conn: conn,
                 domain: :elixir
               )

      assert found.topic == "GenServer"
    end

    test "returns :not_found when no usable brief exists", %{conn: conn} do
      draft = %Brief{sample_brief("b1", :draft) | topic: "GenServer"}
      Store.save_brief(conn, draft)

      assert {:error, :not_found} =
               Coordinator.verified_brief_for("GenServer", :verified_only,
                 conn: conn,
                 domain: :elixir
               )
    end

    test ":any policy returns draft briefs", %{conn: conn} do
      brief = %Brief{sample_brief("b1", :draft) | topic: "Supervisors"}
      Store.save_brief(conn, brief)

      assert {:ok, _} =
               Coordinator.verified_brief_for("Supervisors", :any, conn: conn, domain: :elixir)
    end

    test "returns :not_found when topic does not match", %{conn: conn} do
      brief = %Brief{sample_brief("b1", :usable_for_generation) | topic: "Pattern Matching"}
      Store.save_brief(conn, brief)

      assert {:error, :not_found} =
               Coordinator.verified_brief_for("GenServer", :verified_only,
                 conn: conn,
                 domain: :elixir
               )
    end

    test "topic matching is case-insensitive", %{conn: conn} do
      brief = %Brief{sample_brief("b1", :usable_for_generation) | topic: "GenServer"}
      Store.save_brief(conn, brief)

      assert {:ok, _} =
               Coordinator.verified_brief_for("genserver", :verified_only,
                 conn: conn,
                 domain: :elixir
               )
    end
  end

  describe "investigate_and_save/2" do
    test "saves the brief produced by the agent", %{conn: conn} do
      retriever = fn _conn, _q, _opts ->
        [%{text: "GenServer fact", source_reference: nil, domain: :elixir, metadata: %{}}]
      end

      reviewer = fn _q, chunks -> {:satisfactory, chunks} end

      assert {:ok, brief} =
               Coordinator.investigate_and_save("GenServer",
                 conn: conn,
                 domain: :elixir,
                 retriever: retriever,
                 reviewer: reviewer
               )

      assert {:ok, _} = Store.get_brief(conn, brief.id)
    end

    test "returns error without saving when investigation fails", %{conn: conn} do
      reviewer = fn _q, _chunks -> {:revise, "q", "never"} end
      retriever = fn _conn, _q, _opts -> [] end

      assert {:error, _} =
               Coordinator.investigate_and_save("impossible",
                 conn: conn,
                 domain: :elixir,
                 retriever: retriever,
                 reviewer: reviewer,
                 max_iterations: 1
               )

      {:ok, briefs} = Store.list_briefs(conn)
      assert briefs == []
    end
  end

  describe "promote/2" do
    test "transitions verified brief to usable_for_generation", %{conn: conn} do
      brief = sample_brief("b1", :verified)
      Store.save_brief(conn, brief)

      assert {:ok, promoted} = Coordinator.promote(brief, conn: conn)
      assert promoted.status == :usable_for_generation

      {:ok, loaded} = Store.get_brief(conn, brief.id)
      assert loaded.status == :usable_for_generation
    end

    test "no-op for non-verified briefs (draft stays draft)", %{conn: conn} do
      brief = sample_brief("b1", :draft)
      Store.save_brief(conn, brief)

      {:ok, result} = Coordinator.promote(brief, conn: conn)
      assert result.status == :draft
    end
  end

  describe "expire_stale/2" do
    test "marks expired briefs as stale", %{conn: conn} do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)

      expired = %Brief{
        sample_brief("b1", :usable_for_generation)
        | expires_at: past
      }

      fresh = sample_brief("b2", :usable_for_generation)
      Store.save_brief(conn, expired)
      Store.save_brief(conn, fresh)

      assert {:ok, 1} = Coordinator.expire_stale(conn, domain: :elixir)

      {:ok, loaded_expired} = Store.get_brief(conn, "b1")
      {:ok, loaded_fresh} = Store.get_brief(conn, "b2")

      assert loaded_expired.status == :stale
      assert loaded_fresh.status == :usable_for_generation
    end

    test "returns 0 when no briefs have expired", %{conn: conn} do
      Store.save_brief(conn, sample_brief("b1", :usable_for_generation))
      assert {:ok, 0} = Coordinator.expire_stale(conn, domain: :elixir)
    end
  end

  defp sample_brief(id, status) do
    %Brief{
      id: id,
      domain: :elixir,
      topic: "GenServer",
      status: status,
      facts: ["GenServer serializes access to state"],
      examples: nil,
      prohibited_patterns: nil,
      sources: [],
      package_versions: %{},
      created_at: DateTime.utc_now() |> DateTime.truncate(:second),
      expires_at: nil
    }
  end
end
