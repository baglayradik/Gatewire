import SwiftUI

/// Аккаунт — авторизованная зона: вход, профиль и журнал событий авторизации.
struct AccountView: View {
    @Environment(SessionModel.self) private var session

    var body: some View {
        NavigationStack {
            Form {
                switch session.state {
                case .restoring:
                    ProgressView()

                case .signedOut:
                    LoginSection()

                case let .signedIn(profile):
                    ProfileSection(profile: profile)
                }

                if let errorMessage = session.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                EventLogSection()
            }
            .navigationTitle("Аккаунт")
        }
    }
}

private struct LoginSection: View {
    @Environment(SessionModel.self) private var session

    // Открытые демо-учётные данные из документации DummyJSON.
    @State private var username = "emilys"
    @State private var password = "emilyspass"

    var body: some View {
        Section {
            TextField("Логин", text: $username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
            SecureField("Пароль", text: $password)
                .textContentType(.password)

            Button("Войти") {
                Task { await session.signIn(username: username, password: password) }
            }
            .disabled(session.isBusy || username.isEmpty || password.isEmpty)
        } header: {
            Text("Вход")
        } footer: {
            Text("Демо-аккаунт DummyJSON. Токен живёт одну минуту, чтобы было видно его обновление.")
        }
    }
}

private struct ProfileSection: View {
    @Environment(SessionModel.self) private var session

    let profile: UserProfile

    var body: some View {
        Section("Профиль") {
            HStack(spacing: 12) {
                AsyncImage(url: profile.image) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.secondary.opacity(0.1)
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())

                VStack(alignment: .leading) {
                    Text(profile.fullName)
                        .font(.headline)
                    Text(profile.email)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Обновить профиль") {
                Task { await session.reloadProfile() }
            }
            .disabled(session.isBusy)

            Button("Выйти", role: .destructive) {
                Task { await session.signOut() }
            }
        }
    }
}

private struct EventLogSection: View {
    @Environment(SessionModel.self) private var session

    var body: some View {
        Section("События авторизации") {
            if session.log.isEmpty {
                Text("Пока событий нет")
                    .foregroundStyle(.secondary)
            }

            ForEach(session.log) { entry in
                VStack(alignment: .leading) {
                    Text(entry.text)
                    Text(entry.date, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
