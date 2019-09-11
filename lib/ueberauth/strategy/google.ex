defmodule Ueberauth.Strategy.Google do
  @moduledoc """
  Google Strategy for Überauth.
  """

  use Ueberauth.Strategy, uid_field: :sub, default_scope: "email", hd: nil

  alias Ueberauth.Auth.Info
  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Auth.Extra

  @allowed_client_ids Application.get_env(:ueberauth, Ueberauth.Strategy.Google.OAuth)[:allowed_client_ids]

  @doc """
  Handles initial request for Google authentication.
  """
  def handle_request!(conn) do
    scopes = conn.params["scope"] || option(conn, :default_scope)

    opts =
      [scope: scopes]
      |> with_optional(:hd, conn)
      |> with_optional(:approval_prompt, conn)
      |> with_optional(:access_type, conn)
      |> with_param(:access_type, conn)
      |> with_param(:prompt, conn)
      |> with_param(:state, conn)
      |> Keyword.put(:redirect_uri, callback_url(conn))

    redirect!(conn, Ueberauth.Strategy.Google.OAuth.authorize_url!(opts))
  end

  @doc """
  Handles the callback from Google.
  """
  def handle_callback!(%Plug.Conn{params: %{"code" => code}} = conn) do
    opts = [redirect_uri: callback_url(conn)]
    token = Ueberauth.Strategy.Google.OAuth.get_token!([code: code], opts)

    if token.access_token == nil do
      set_errors!(conn, [error(token.other_params["error"], token.other_params["error_description"])])
    else
      fetch_user(conn, token)
    end
  end

  @doc """
  Handles the callback from app.
  """
  def handle_callback!(%Plug.Conn{params: %{"id_token" => id_token}} = conn) do
    client = Ueberauth.Strategy.Google.OAuth.client
    case verify_token(conn, client, id_token) do
      {:ok, user} ->
        conn
        |> put_private(:google_token, OAuth2.AccessToken.new(id_token))
        |> put_private(:google_user, user)
      {:error, reason} ->
        set_errors!(conn, [error("token", reason)])
    end
  end

  @doc false
  def handle_callback!(conn) do
    set_errors!(conn, [error("missing_code", "No code received")])
  end

  @doc false
  def handle_cleanup!(conn) do
    conn
    |> put_private(:google_user, nil)
    |> put_private(:google_token, nil)
  end

  @doc """
  Fetches the uid field from the response.
  """
  def uid(conn) do
    uid_field =
      conn
      |> option(:uid_field)
      |> to_string

    conn.private.google_user[uid_field]
  end

  @doc """
  Includes the credentials from the google response.
  """
  def credentials(conn) do
    token        = conn.private.google_token
    scope_string = (token.other_params["scope"] || "")
    scopes       = String.split(scope_string, ",")

    %Credentials{
      expires: !!token.expires_at,
      expires_at: token.expires_at,
      scopes: scopes,
      token_type: Map.get(token, :token_type),
      refresh_token: token.refresh_token,
      token: token.access_token
    }
  end

  @doc """
  Fetches the fields to populate the info section of the `Ueberauth.Auth` struct.
  """
  def info(conn) do
    user = conn.private.google_user

    %Info{
      email: user["email"],
      first_name: user["given_name"],
      image: user["picture"],
      last_name: user["family_name"],
      name: user["name"],
      urls: %{
        profile: user["profile"],
        website: user["hd"]
      }
    }
  end

  @doc """
  Stores the raw information (including the token) obtained from the google callback.
  """
  def extra(conn) do
    %Extra{
      raw_info: %{
        token: conn.private.google_token,
        user: conn.private.google_user
      }
    }
  end


  defp fetch_user(conn, token) do
    conn = put_private(conn, :google_token, token)

    # userinfo_endpoint from https://accounts.google.com/.well-known/openid-configuration
    path = "https://www.googleapis.com/oauth2/v3/userinfo"
    resp = Ueberauth.Strategy.Google.OAuth.get(token, path)

    case resp do
      {:ok, %OAuth2.Response{status_code: 401, body: _body}} ->
        set_errors!(conn, [error("token", "unauthorized")])
      {:ok, %OAuth2.Response{status_code: status_code, body: user}} when status_code in 200..399 ->
        put_private(conn, :google_user, user)
      {:error, %OAuth2.Error{reason: reason}} ->
        set_errors!(conn, [error("OAuth2", reason)])
    end
  end

  defp with_param(opts, key, conn) do
    if value = conn.params[to_string(key)], do: Keyword.put(opts, key, value), else: opts
  end

  defp with_optional(opts, key, conn) do
    if option(conn, key), do: Keyword.put(opts, key, option(conn, key)), else: opts
  end

  defp option(conn, key) do
    Keyword.get(options(conn), key, Keyword.get(default_options(), key))
  end

  def verify_token(conn, client, id_token) do
    url = "https://www.googleapis.com/oauth2/v3/tokeninfo"
    params = %{"id_token" => id_token}
    resp = OAuth2.Client.get(client, url, [], params: params)

    case resp do
      {:ok, %OAuth2.Response{status_code: 200,
        body: %{"aud" => aud} = body
      }} ->
        if Enum.member?(@allowed_client_ids, aud) do
          {:ok, body}
        else
          {:error, "Unknown client id #{aud}"}
        end
      _ ->
        {:error, "Token verification failed"}
    end
  end
end
