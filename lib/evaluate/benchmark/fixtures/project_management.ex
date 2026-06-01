defmodule Evaluate.Benchmark.Fixtures.ProjectManagement do
  @behaviour Evaluate.Benchmark.Domain

  alias Evaluate.Benchmark.Fixture

  @impl true
  def name, do: "Project Management"

  @impl true
  def categories do
    [:estimation, :prioritization, :communication, :risk, :process, :decision_making]
  end

  @impl true
  def fixtures do
    [
      %Fixture{
        id: "pm-estimate-001",
        category: :estimation,
        difficulty: :medium,
        prompt: """
        A stakeholder asks "how long will the new reporting feature take?"
        You have never built it before and the spec is still vague.
        Walk through how you would produce an honest estimate: what questions
        you ask first, what decomposition technique you use, how you express
        uncertainty (range vs point estimate), and what you say when pushed
        for a specific date you don't believe in.
        """,
        test_code: nil,
        tags: [:estimation, :uncertainty, :communication, :explanation],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "pm-estimate-002",
        category: :estimation,
        difficulty: :medium,
        prompt: """
        Your team consistently underestimates by 40%. You use story points and
        two-week sprints. Describe three concrete interventions — with rationale —
        that have a realistic chance of improving estimation accuracy within two quarters.
        Avoid generic advice like "break tasks down more."
        """,
        test_code: nil,
        tags: [:estimation, :calibration, :process_improvement],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "pm-priority-001",
        category: :prioritization,
        difficulty: :medium,
        prompt: """
        You have 12 items in the backlog, limited engineering capacity, and three
        stakeholders each claiming their work is most important. Describe a prioritization
        framework you would facilitate, how you make the trade-offs explicit, how you
        handle a stakeholder who escalates to leadership, and how you document the decision.
        """,
        test_code: nil,
        tags: [:prioritization, :stakeholder_management, :frameworks],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "pm-comms-001",
        category: :communication,
        difficulty: :easy,
        prompt: """
        A critical bug is in production affecting 15% of users. It's 4pm on a Friday.
        Write: (1) the initial Slack message to the engineering team, (2) the status
        page update for customers, and (3) the executive summary email 2 hours later
        once the fix is deployed. Calibrate the tone and detail level for each audience.
        """,
        test_code: nil,
        tags: [:communication, :incident_response, :writing],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "pm-risk-001",
        category: :risk,
        difficulty: :medium,
        prompt: """
        Your team is about to migrate a production database with 10M rows and no
        downtime window. Identify the top five risks, rate each by likelihood and
        impact, and describe the mitigation and rollback plan for the two highest-rated risks.
        """,
        test_code: nil,
        tags: [:risk, :migration, :planning],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "pm-process-001",
        category: :process,
        difficulty: :medium,
        prompt: """
        A new team member says "we should switch from Scrum to Kanban." You are the
        tech lead. How do you evaluate the proposal? What signals in the current process
        would make you lean toward Kanban? What would make you keep Scrum? How do you
        make the decision without it becoming a political debate?
        """,
        test_code: nil,
        tags: [:process, :scrum, :kanban, :decision_making],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "pm-decision-001",
        category: :decision_making,
        difficulty: :hard,
        prompt: """
        You must choose between: (A) shipping a feature that is 80% done but has a
        known performance issue under load; (B) delaying the launch by 3 weeks to fix it.
        Marketing has already announced the launch date. Describe the information you
        gather, how you frame the decision for stakeholders, what your recommendation
        process looks like, and how you document and communicate the final call.
        """,
        test_code: nil,
        tags: [:decision_making, :trade_offs, :stakeholders, :shipping],
        scoreable: false,
        sandbox_profile: nil
      }
    ]
  end
end
