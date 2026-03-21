import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { checkFileSizeLimit } from 'shared/helpers/FileHelper';
import { getMaxUploadSizeByChannel } from '@chatwoot/utils';
import { DirectUpload } from 'activestorage';
import {
  DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE,
  resolveMaximumFileUploadSize,
} from 'shared/helpers/FileHelper';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

export default {
  computed: {
    ...mapGetters({
      accountId: 'getCurrentAccountId',
    }),
    installationLimit() {
      return resolveMaximumFileUploadSize(
        this.globalConfig.maximumFileUploadSize
      );
    },
  },

  methods: {
    maxSizeFor(mime) {
      // Use default/installation limit for private notes
      if (this.isOnPrivateNote) {
        return this.installationLimit;
      }

      const channelType = this.inbox?.channel_type;

      if (!channelType || channelType === INBOX_TYPES.WEB) {
        return this.installationLimit;
      }

      // Bypass strict limits for Whatsapp / Evolution API
      if (channelType === 'Channel::Whatsapp') {
        return 500;
      }

      const channelLimit = getMaxUploadSizeByChannel({
        channelType,
        medium: this.inbox?.medium, // e.g. 'sms' | 'whatsapp'
        mime, // e.g. 'image/png'
      });

      if (channelLimit === DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE) {
        return this.installationLimit;
      }

      return Math.min(channelLimit, this.installationLimit);
    },
    alertOverLimit(maxSizeMB) {
      useAlert(
        this.$t('CONVERSATION.FILE_SIZE_LIMIT', {
          MAXIMUM_SUPPORTED_FILE_UPLOAD_SIZE: maxSizeMB,
        })
      );
    },
    onFileUpload(file) {
      if (this.globalConfig.directUploadsEnabled) {
        this.onDirectFileUpload(file);
      } else {
        this.onIndirectFileUpload(file);
      }
    },

    onDirectFileUpload(file) {
      if (!file) return;

      const mime = file.file?.type || file.type;
      const maxSizeMB = this.maxSizeFor(mime);

      if (!checkFileSizeLimit(file, maxSizeMB)) {
        this.alertOverLimit(maxSizeMB);
        return;
      }

      // Add a unique ID to the file object to track its progress
      const fileId = Date.now().toString(36) + Math.random().toString(36).substr(2);
      file.id = fileId;

      if (typeof this.attachFile === 'function') {
        this.attachFile({ file, isUploading: true, progress: 0 });
      }

      const upload = new DirectUpload(
        file.file,
        `/api/v1/accounts/${this.accountId}/conversations/${this.currentChat.id}/direct_uploads`,
        {
          directUploadWillCreateBlobWithXHR: xhr => {
            xhr.setRequestHeader(
              'api_access_token',
              this.currentUser.access_token
            );
          },
          directUploadWillStoreFileWithXHR: request => {
            request.upload.addEventListener('progress', event => {
              if (event.lengthComputable) {
                const progress = Math.round((event.loaded / event.total) * 100);
                if (typeof this.updateUploadProgress === 'function') {
                  this.updateUploadProgress(fileId, progress);
                }
              }
            });
          },
        }
      );

      upload.create((error, blob) => {
        if (error) {
          useAlert(error);
          if (typeof this.removeAttachmentById === 'function') {
            this.removeAttachmentById(fileId);
          }
        } else {
          if (typeof this.finishAttachment === 'function') {
            this.finishAttachment(fileId, { file, blob });
          } else {
            this.attachFile({ file, blob });
          }
        }
      });
    },

    onIndirectFileUpload(file) {
      if (!file) return;

      const mime = file.file?.type || file.type;
      const maxSizeMB = this.maxSizeFor(mime);

      if (!checkFileSizeLimit(file, maxSizeMB)) {
        this.alertOverLimit(maxSizeMB);
        return;
      }

      this.attachFile({ file });
    },
  },
};
