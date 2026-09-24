import SwiftUI

extension SettingsViewModel {
    func saveAIKey() {
        do {
            let config = try draft.aiChat.validated()
            _ = try config.requestURL()
            try AIChatKeychain.save(aiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines), endpoint: config.endpoint)
            aiKeyDraft = ""
            aiStatus = uiText("密钥已存入钥匙串。点“应用”保存其他设置。", "Key saved in Keychain. Select Apply to save the other settings.")
        } catch { aiStatus = uiText("无法保存密钥，请检查地址和钥匙串权限。", "Could not save the key. Check the endpoint and Keychain access.") }
    }

    func testAIConnection() {
        guard !aiTesting else { return }
        aiTesting = true
        aiStatus = uiText("正在测试……", "Testing…")
        let draft = draft.aiChat
        let keyDraft = aiKeyDraft
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.aiTesting = false }
            do {
                let config = try draft.validated()
                guard !config.model.isEmpty else { throw AIChatError.configuration }
                let key = keyDraft.isEmpty ? try AIChatKeychain.read(endpoint: config.endpoint) : keyDraft
                let response = try await AIChatHTTPTransport().complete(configuration: config, key: key, messages: [
                    .init(role: "system", content: "Return only JSON: {\"text\":\"…Hello.\",\"options\":[\"Hi\",\"Stay a while\"],\"emotion\":\"neutral\"}."),
                    .init(role: "user", content: "Connection test. No personal data.")
                ])
                _ = try AIChatTurn.decode(response, english: true)
                guard self.draft.aiChat == draft, self.aiKeyDraft == keyDraft else {
                    self.aiStatus = self.uiText("设置已改变，请重新测试。", "Settings changed. Please test again."); return
                }
                self.aiStatus = self.uiText("连接和回复格式正常。", "Connection and reply format verified.")
            } catch {
                self.aiStatus = (error as? AIChatError).map { InterfaceLanguage.authored($0.message(english: self.draft.ui.locale == "en"), locale: self.draft.ui.locale) }
                    ?? self.uiText("连接超时或不可用。", "Connection unavailable or timed out.")
            }
        }
    }

    func refreshAIMemory() {
        aiFacts = runtime.chatMemory.state.facts
        aiMemoryBytes = runtime.chatMemory.bytesUsed
    }

    func addAIMemory() {
        do {
            try runtime.chatMemory.remember(aiMemoryDraft, spokenAt: AIChatTimestamp())
            aiMemoryDraft = ""
            refreshAIMemory()
        } catch { aiStatus = uiText("无法保存记忆，已有数据保持不变。", "Could not save memory. Existing data was preserved.") }
    }

    func deleteAIMemory(_ id: UUID?) {
        do {
            if let id { try runtime.chatMemory.forget(id) } else { try runtime.chatMemory.clear() }
            NotificationCenter.default.post(name: .aiChatMemoryCleared, object: runtime.chatMemory)
            refreshAIMemory()
            aiStatus = uiText("已清理记忆和相关聊天上下文。", "Memory and related chat context cleared.")
        } catch { aiStatus = uiText("无法清理记忆，已有数据保持不变。", "Could not clear memory. Existing data was preserved.") }
    }
}

extension Notification.Name {
    static let aiChatMemoryCleared = Notification.Name("BlobfishAIChatMemoryCleared")
}

struct AIChatSettingsView: View {
    @ObservedObject var model: SettingsViewModel
    @State private var expanded = false
    @State private var showMemories = false
    @State private var confirmClear = false
    private func t(_ zh: InterfaceText, _ en: InterfaceText) -> String { model.uiText(zh, en) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { expanded.toggle() } label: {
                HStack {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    Text(t("AI 聊天", "AI chat")).font(.headline)
                    Spacer()
                    Text(model.draft.aiChat.enabled ? t("已启用", "Enabled") : t("本地台词", "Local dialogue")).foregroundStyle(.secondary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if expanded {
                Toggle(t("启用 AI 聊天", "Enable AI chat"), isOn: $model.draft.aiChat.enabled)
                Text(t("不启用时保留原有台词和小游戏。支持 Chat Completions 兼容接口。", "When disabled, authored dialogue and local games remain available. Supports Chat Completions compatible endpoints."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(t("陪伴时的闲聊兴趣", "Shared conversation interests")).font(.caption).foregroundStyle(.secondary)
                TextField(t("例如：日常小事、喜好、小期待、宠物日常", "For example: everyday moments, preferences, little plans, pet life"), text: $model.draft.aiChat.topicScope)
                    .textFieldStyle(.roundedBorder)
                Text(t("鱼会顺着你的心情和正在聊的事回应，偶尔提起你分享过的小事。这里是闲聊兴趣，不是问题清单；也可以安静陪着，不必每句都回答问题。", "Your pet follows your mood and the conversation, sometimes picking up something you shared. These are interests, not a questionnaire; quiet company is welcome too."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(t("API 地址", "API address")).font(.caption).foregroundStyle(.secondary)
                TextField(t("基础地址或完整聊天接口地址", "Base URL or full chat endpoint"), text: $model.draft.aiChat.endpoint)
                    .textFieldStyle(.roundedBorder)
                if let resolved = try? model.draft.aiChat.validated().requestURL() {
                    Text(t("实际请求：\(resolved.absoluteString)", "Request URL: \(resolved.absoluteString)"))
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                TextField(t("模型名称", "Model name"), text: $model.draft.aiChat.model).textFieldStyle(.roundedBorder)
                SecureField(t("API Key（留空保留该地址已保存的密钥）", "API key (leave empty to keep the saved key for this endpoint)"), text: $model.aiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button(t("保存密钥", "Save key")) { model.saveAIKey() }.disabled(model.aiKeyDraft.isEmpty)
                    Button(t("测试连接", "Test connection")) { model.testAIConnection() }.disabled(model.aiTesting)
                    if model.aiTesting { ProgressView().controlSize(.small) }
                }
                Text(t("测试会发送一条无个人内容的请求，可能计入服务用量。聊天时仅发送当前对话和选取的记忆；不会读取桌面文件或好友消息。", "Testing sends one request without personal content and may count toward provider usage. Chats send only conversation context and selected memories, never desktop files or friend messages."))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(t("保存本地聊天记忆", "Save local chat memory"), isOn: $model.draft.aiChat.memoryEnabled)
                Text(t("最多 \(AIChatMemoryStore.entryCountLimit * 2) 条聊天消息、\(AIChatMemoryStore.factCountLimit) 条长期记忆，总占用（含写入临时文件）不超过 \(AIChatMemoryStore.totalDiskLimit / (1024 * 1024)) MB。关闭后仅保留本次窗口上下文，不写入也不发送旧记忆。", "Up to \(AIChatMemoryStore.entryCountLimit * 2) chat messages and \(AIChatMemoryStore.factCountLimit) saved notes; total storage including temporary writes stays within \(AIChatMemoryStore.totalDiskLimit / (1024 * 1024)) MB. When disabled, only this window's context is used; saved memory is neither read into requests nor updated."))
                    .font(.caption).foregroundStyle(.secondary)
                Button { showMemories.toggle(); model.refreshAIMemory() } label: {
                    Label(t("鱼记住了什么", "What your fish remembers"), systemImage: showMemories ? "chevron.down" : "chevron.right")
                }.buttonStyle(.plain)
                if showMemories {
                    Text(t("说“记住……”或从聊天菜单保存一句话。删除单条记忆也会清空近期上下文，避免旧聊天再次带回它。", "Say ‘remember…’ or save a message from the chat menu. Deleting a note also clears recent context so old chats cannot bring it back."))
                        .font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(model.aiFacts) { fact in
                                HStack(alignment: .top) {
                                    Text(fact.text).textSelection(.enabled)
                                    Spacer()
                                    Button { model.deleteAIMemory(fact.id) } label: { Image(systemName: "trash") }
                                        .help(t("删除", "Delete"))
                                }
                            }
                        }
                    }.frame(height: model.aiFacts.isEmpty ? 0 : 150)
                    HStack {
                        TextField(t("添加一条想让鱼记住的事", "Add something for your fish to remember"), text: $model.aiMemoryDraft)
                        Button(t("记住", "Remember")) { model.addAIMemory() }.disabled(model.aiMemoryDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    HStack {
                        Text(t("已用：\(model.aiMemoryBytes / 1024) KB", "Used: \(model.aiMemoryBytes / 1024) KB")).font(.caption)
                        Spacer()
                        Button(t("清空全部记忆和记录", "Clear all memory and history")) { confirmClear = true }
                    }
                }
                if !model.aiStatus.isEmpty { Text(model.aiStatus).font(.caption).textSelection(.enabled) }
            }
        }
        .onAppear { model.refreshAIMemory() }
        .alert(t("清空聊天记忆？", "Clear chat memory?"), isPresented: $confirmClear) {
            Button(t("清空", "Clear"), role: .destructive) { model.deleteAIMemory(nil) }
            Button(t("取消", "Cancel"), role: .cancel) {}
        } message: { Text(t("仅清理和桌宠的 AI 聊天记录与记忆，好友传话不受影响。", "Clears only AI pet chat history and memory. Friend messages are unaffected.")) }
    }
}
