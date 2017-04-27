defmodule CaptainFact.UserController do
  use CaptainFact.Web, :controller

  alias CaptainFact.User
  alias CaptainFact.SendInBlueApi

  plug Guardian.Plug.EnsureAuthenticated, [handler: CaptainFact.AuthController]
  when action in [:search, :update, :admin_logout]

  def create(conn, %{"user" => user_params}) do
    changeset = User.changeset(%User{}, user_params)

    case Repo.insert(changeset) do
      {:ok, user} ->
        {:ok, token, _claims} = Guardian.encode_and_sign(user, :token)
        conn
        |> put_status(:created)
        |> render("show.json", user: user, token: token)
      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> render(CaptainFact.ChangesetView, "error.json", changeset: changeset)
    end
  end

  def show(conn, %{"username" => username}) do
    current_user = Guardian.Plug.current_resource(conn)
    if (current_user && current_user.username == username) do
      render(conn, "show.json", user: current_user)
    else
      render(conn, "show_public.json", user: Repo.get_by!(User, username: username))
    end
  end

  def admin_login(conn, _) do
    render(conn, "admin_login.html")
  end

  def admin_logout(conn, _) do
    conn
      |> Guardian.Plug.current_token
      |> Guardian.revoke!
    conn
      |> Plug.Conn.configure_session(drop: true)
      |> redirect(to: "/admin/login")
  end

  def update(conn, params = %{"user_id" => user_id}) do
    user_id = String.to_integer(user_id)
    current_user = Guardian.Plug.current_resource(conn)
    case current_user.id === user_id do
      false -> send_resp(conn, 401, "Unauthorized")
      true ->
        Repo.get!(User, user_id)
        |> User.changeset(params)
        |> Repo.update()
        |> case do
          {:ok, user} ->
            render(conn, :show, user: user)
          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> render(CaptainFact.ChangesetView, :error, changeset: changeset)
        end
    end
  end

  def newsletter_subscribe(conn, %{"email" => email}) do
    case Regex.match?(~r/@/, email) do
      false -> render_invalid_email_error(conn)
      true -> case ForbiddenEmailProviders.is_forbidden(email) do
        true -> render_invalid_email_error(conn)
        false ->
          %SendInBlueApi.User{email: email}
          |> SendInBlueApi.User.create_or_update()
          |> case do
            {:ok, _} -> send_resp(conn, 200, "")
            {:error, _} -> render_invalid_email_error(conn, "Email rejected")
          end
      end
    end
  end

  defp render_invalid_email_error(conn, msg \\ "Invalid Email") do
    conn |> put_status(400) |> json(%{error: msg})
  end

  #
  # def delete(conn, %{"id" => id}) do
  #   user = Repo.get!(User, id)
  #
  #   # Here we use delete! (with a bang) because we expect
  #   # it to always work (and if it does not, it will raise).
  #   Repo.delete!(user)
  #
  #   send_resp(conn, :no_content, "")
  # end
end
