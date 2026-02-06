/**
 * 🔔 PUSH IMEDIATO (OPÇÃO 2 - MULTI TOKEN)
 * Dispara PUSH para TODOS os dispositivos ativos do usuário
 * quando um documento é criado em: notificacoes/{id}
 */

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getMessaging } = require("firebase-admin/messaging");
const { getFirestore } = require("firebase-admin/firestore");

initializeApp();

exports.enviarNotificacao = onDocumentCreated(
  "notificacoes/{id}",
  async (event) => {
    try {
      const snapshot = event.data;
      if (!snapshot) return;

      const data = snapshot.data();
      if (!data) return;

      const uid = data.uid;
      if (!uid) {
        console.log("❌ uid não informado no documento");
        return;
      }

      // 🔹 Busca TODOS os tokens ativos do usuário
      const tokensSnap = await getFirestore()
        .collection("usuarios")
        .doc(uid)
        .collection("fcmTokens")
        .where("enabled", "==", true)
        .get();

      if (tokensSnap.empty) {
        console.log("⚠️ Nenhum token ativo para o usuário");
        return;
      }

      const tokens = tokensSnap.docs.map((d) => d.id);

      const message = {
        notification: {
          title: data.titulo ?? "ImunizaKids",
          body: data.mensagem ?? "Você tem uma nova notificação",
        },
        data: {
          rota: data.rota ?? "",
          filhoId: data.filhoId ?? "",
        },
        android: {
          priority: "high",
        },
      };

      // 🚀 Envia para TODOS os dispositivos
      const response = await getMessaging().sendEachForMulticast({
        tokens,
        ...message,
      });

      console.log(
        `✅ PUSH enviado: ${response.successCount} sucesso(s), ${response.failureCount} falha(s)`
      );

      // 🔕 Desabilita tokens inválidos
      response.responses.forEach(async (res, idx) => {
        if (!res.success) {
          const token = tokens[idx];
          await getFirestore()
            .collection("usuarios")
            .doc(uid)
            .collection("fcmTokens")
            .doc(token)
            .set(
              {
                enabled: false,
                disabledAt: new Date(),
                disableReason: res.error?.code ?? "unknown",
              },
              { merge: true }
            );
        }
      });
    } catch (error) {
      console.error("❌ Erro ao enviar PUSH:", error);
    }
  }
);
