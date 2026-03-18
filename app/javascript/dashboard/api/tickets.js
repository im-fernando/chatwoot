/* global axios */
import ApiClient from './ApiClient';

class TicketsAPI extends ApiClient {
  constructor() {
    super('tickets', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }

  linkConversation(ticketDisplayId, conversationDisplayId) {
    return axios.post(`${this.url}/${ticketDisplayId}/conversations`, {
      ticket_conversation: { conversation_display_id: conversationDisplayId },
    });
  }

  unlinkConversation(ticketDisplayId, conversationDisplayId) {
    return axios.delete(
      `${this.url}/${ticketDisplayId}/conversations/${conversationDisplayId}`
    );
  }

  getComments(ticketDisplayId) {
    return axios.get(`${this.url}/${ticketDisplayId}/comments`);
  }

  addComment(ticketDisplayId, content) {
    return axios.post(`${this.url}/${ticketDisplayId}/comments`, {
      ticket_comment: { content },
    });
  }
}

export default new TicketsAPI();
