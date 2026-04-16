defmodule ScrumPoker.RoomPresence do
  use Phoenix.Presence,
    otp_app: :scrum_poker,
    pubsub_server: ScrumPoker.PubSub
end
