defmodule ScrumPokerWeb.UserLive.Settings do
  use ScrumPokerWeb, :live_view

  on_mount {ScrumPokerWeb.UserAuth, :require_sudo_mode}

  alias ScrumPoker.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="text-center">
        <.header>
          Account Settings
          <:subtitle>Manage your profile, email, and password</:subtitle>
        </.header>
      </div>

      <%!-- Profile section --%>
      <.form for={@profile_form} id="profile_form" phx-submit="update_profile" phx-change="validate_profile">
        <div class="flex items-center gap-6 mb-4">
          <div class="avatar">
            <div class="w-20 h-20 rounded-full bg-base-300 flex items-center justify-center overflow-hidden">
              <%= if entry = List.first(@uploads.avatar.entries) do %>
                <.live_img_preview entry={entry} class="w-full h-full object-cover" />
              <% else %>
                <%= if @current_avatar_url do %>
                  <img src={@current_avatar_url} class="w-full h-full object-cover" />
                <% else %>
                  <span class="text-3xl text-base-content/30">
                    {String.first(@current_scope.user.display_name || @current_scope.user.email)}
                  </span>
                <% end %>
              <% end %>
            </div>
          </div>
          <div class="flex-1 space-y-2">
            <label class="btn btn-sm btn-outline cursor-pointer">
              <.icon name="hero-camera" class="size-4" /> Change photo
              <.live_file_input upload={@uploads.avatar} class="hidden" />
            </label>
            <p :for={entry <- @uploads.avatar.entries} class="text-xs text-base-content/60">
              {entry.client_name}
              <button type="button" phx-click="cancel_upload" phx-value-ref={entry.ref}
                      class="text-error ml-1">&times;</button>
            </p>
            <p :for={err <- upload_errors(@uploads.avatar)} class="text-xs text-error">
              {upload_error_message(err)}
            </p>
          </div>
        </div>

        <.input
          field={@profile_form[:display_name]}
          label="Display Name"
          placeholder="How others see you"
          autocomplete="name"
        />
        <.button variant="primary" phx-disable-with="Saving...">Save Profile</.button>
      </.form>

      <div class="divider" />

      <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email">
        <.input
          field={@email_form[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          spellcheck="false"
          required
        />
        <.button variant="primary" phx-disable-with="Changing...">Change Email</.button>
      </.form>

      <div class="divider" />

      <.form
        for={@password_form}
        id="password_form"
        action={~p"/users/update-password"}
        method="post"
        phx-change="validate_password"
        phx-submit="update_password"
        phx-trigger-action={@trigger_submit}
      >
        <input
          name={@password_form[:email].name}
          type="hidden"
          id="hidden_user_email"
          spellcheck="false"
          value={@current_email}
        />
        <.input
          field={@password_form[:password]}
          type="password"
          label="New password"
          autocomplete="new-password"
          spellcheck="false"
          required
        />
        <.input
          field={@password_form[:password_confirmation]}
          type="password"
          label="Confirm new password"
          autocomplete="new-password"
          spellcheck="false"
        />
        <.button variant="primary" phx-disable-with="Saving...">
          Save Password
        </.button>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)
    profile_changeset = Accounts.change_user_profile(user, %{})

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:current_avatar_url, user.avatar_url)
      |> assign(:avatar_preview, nil)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:profile_form, to_form(profile_changeset))
      |> assign(:trigger_submit, false)
      |> allow_upload(:avatar, accept: ~w(.jpg .jpeg .png .gif .webp), max_entries: 1, max_file_size: 2_000_000)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_profile", %{"user" => params}, socket) do
    profile_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_profile(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, profile_form: profile_form)}
  end

  def handle_event("update_profile", %{"user" => params}, socket) do
    user = socket.assigns.current_scope.user

    avatar_url =
      case consume_uploaded_entries(socket, :avatar, &save_avatar/2) do
        [path] -> path
        [] -> user.avatar_url
      end

    params = Map.put(params, "avatar_url", avatar_url)

    case Accounts.update_user_profile(user, params) do
      {:ok, user} ->
        profile_form = Accounts.change_user_profile(user, %{}) |> to_form()

        {:noreply,
         socket
         |> assign(:current_avatar_url, user.avatar_url)
         |> assign(:avatar_preview, nil)
         |> assign(:profile_form, profile_form)
         |> put_flash(:info, "Profile updated.")}

      {:error, changeset} ->
        {:noreply, assign(socket, profile_form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :avatar, ref)}
  end

  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  defp save_avatar(%{path: path}, entry) do
    ext = Path.extname(entry.client_name)
    filename = "avatar_#{entry.uuid}#{ext}"
    dest = Path.join(["priv", "static", "uploads", filename])
    File.cp!(path, dest)
    {:ok, "/uploads/#{filename}"}
  end

  defp upload_error_message(:too_large), do: "Image must be under 2 MB."
  defp upload_error_message(:too_many_files), do: "Only one image allowed."
  defp upload_error_message(:not_accepted), do: "Must be JPG, PNG, GIF, or WebP."
  defp upload_error_message(_), do: "Upload error."
end
