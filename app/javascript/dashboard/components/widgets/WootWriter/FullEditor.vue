<script>
import {
  fullSchema,
  buildEditor,
  EditorView,
  ArticleMarkdownSerializer,
  ArticleMarkdownTransformer,
  EditorState,
  Selection,
} from '@chatwoot/prosemirror-schema';
import imagePastePlugin from '@chatwoot/prosemirror-schema/src/plugins/image';
import { checkFileSizeLimit } from 'shared/helpers/FileHelper';
import { useAlert } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import keyboardEventListenerMixins from 'shared/mixins/keyboardEventListenerMixins';

const MAXIMUM_FILE_UPLOAD_SIZE = 150; // in MB
const createState = (
  content,
  placeholder,
  // eslint-disable-next-line default-param-last
  plugins = [],
  // eslint-disable-next-line default-param-last
  methods = {},
  enabledMenuOptions
) => {
  return EditorState.create({
    doc: new ArticleMarkdownTransformer(fullSchema).parse(content),
    plugins: buildEditor({
      schema: fullSchema,
      placeholder,
      methods,
      plugins,
      enabledMenuOptions,
    }),
  });
};

let editorView = null;
let state;

export default {
  mixins: [keyboardEventListenerMixins],
  props: {
    modelValue: { type: String, default: '' },
    editorId: { type: String, default: '' },
    placeholder: { type: String, default: '' },
    enabledMenuOptions: { type: Array, default: () => [] },
    autofocus: {
      type: Boolean,
      default: true,
    },
  },
  emits: ['blur', 'input', 'update:modelValue', 'keyup', 'focus', 'keydown'],
  setup() {
    const { uiSettings, updateUISettings } = useUISettings();

    return {
      uiSettings,
      updateUISettings,
    };
  },
  data() {
    return {
      plugins: [imagePastePlugin(this.handleImageUpload)],
      isTextSelected: false, // Tracks text selection and prevents unnecessary re-renders on mouse selection
    };
  },
  watch: {
    modelValue(newValue = '') {
      if (newValue !== this.contentFromEditor()) {
        this.reloadState();
      }
    },
    editorId() {
      this.reloadState();
    },
  },

  created() {
    state = createState(
      this.modelValue || '',
      this.placeholder,
      this.plugins,
      { onImageUpload: this.openFileBrowser },
      this.enabledMenuOptions
    );
  },
  mounted() {
    this.createEditorView();

    editorView.updateState(state);
    if (this.autofocus) {
      this.focusEditorInputField();
    }
  },
  methods: {
    contentFromEditor() {
      if (editorView) {
        return ArticleMarkdownSerializer.serialize(editorView.state.doc);
      }
      return '';
    },
    openFileBrowser() {
      this.$refs.imageUploadInput.click();
    },
    async handleImageUpload(url) {
      try {
        const fileUrl = await this.$store.dispatch(
          'articles/uploadExternalImage',
          {
            portalSlug: this.$route.params.portalSlug,
            url,
          }
        );

        return fileUrl;
      } catch (error) {
        useAlert(
          this.$t('HELP_CENTER.ARTICLE_EDITOR.IMAGE_UPLOAD.UN_AUTHORIZED_ERROR')
        );
        return '';
      }
    },
    onFileChange() {
      const file = this.$refs.imageUploadInput.files[0];
      if (!file) return;

      if (checkFileSizeLimit(file, MAXIMUM_FILE_UPLOAD_SIZE)) {
        this.uploadArticleAttachment(file);
      } else {
        useAlert(
          this.$t('HELP_CENTER.ARTICLE_EDITOR.FILE_UPLOAD.ERROR_FILE_SIZE', {
            size: MAXIMUM_FILE_UPLOAD_SIZE,
          })
        );
      }

      this.$refs.imageUploadInput.value = '';
    },
    isDisplayableImage(file) {
      if (!file) return false;
      const { type, name } = file;
      if (type && type.startsWith('image/')) return true;
      const ext = name?.split('.').pop()?.toLowerCase();
      return [
        'png',
        'jpg',
        'jpeg',
        'gif',
        'webp',
        'bmp',
        'svg',
        'ico',
      ].includes(ext);
    },
    insertUploadedAsset(fileUrl, file) {
      const { schema } = editorView.state;
      const { from } = editorView.state.selection;

      if (this.isDisplayableImage(file)) {
        const node = schema.nodes.image.create({ src: fileUrl });
        const paragraphNode = schema.node('paragraph');
        const tr = editorView.state.tr
          .replaceSelectionWith(paragraphNode)
          .insert(from + 1, node);
        editorView.dispatch(tr.scrollIntoView());
      } else {
        const linkMark = schema.mark('link', { href: fileUrl });
        const label =
          file?.name ||
          this.$t('HELP_CENTER.ARTICLE_EDITOR.FILE_UPLOAD.LINK_FALLBACK');
        const prefix = `${this.$t(
          'HELP_CENTER.ARTICLE_EDITOR.FILE_UPLOAD.DOWNLOAD_PREFIX'
        )} `;
        const prefixNode = schema.text(prefix);
        const linkNode = schema.text(label, [linkMark]);
        const paragraphWithLink = schema.node('paragraph', null, [
          prefixNode,
          linkNode,
        ]);
        editorView.dispatch(
          editorView.state.tr
            .replaceSelectionWith(paragraphWithLink)
            .scrollIntoView()
        );
      }
      this.focusEditorInputField();
    },
    async uploadArticleAttachment(file) {
      try {
        const fileUrl = await this.$store.dispatch('articles/attachImage', {
          portalSlug: this.$route.params.portalSlug,
          file,
        });

        if (fileUrl) {
          this.insertUploadedAsset(fileUrl, file);
        }
      } catch (error) {
        useAlert(this.$t('HELP_CENTER.ARTICLE_EDITOR.FILE_UPLOAD.ERROR'));
      }
    },
    reloadState() {
      state = createState(
        this.modelValue || '',
        this.placeholder,
        this.plugins,
        { onImageUpload: this.openFileBrowser },
        this.enabledMenuOptions
      );
      editorView.updateState(state);
      this.focusEditorInputField();
    },
    createEditorView() {
      editorView = new EditorView(this.$refs.editor, {
        state: state,
        dispatchTransaction: tx => {
          state = state.apply(tx);
          editorView.updateState(state);
          if (tx.docChanged) {
            this.emitOnChange();
          }
          this.checkSelection(state);
        },
        handleDOMEvents: {
          keyup: this.onKeyup,
          focus: this.onFocus,
          blur: this.onBlur,
          keydown: this.onKeydown,
          paste: (view, event) => {
            const data = event.clipboardData.files;
            if (data.length > 0) {
              Array.from(data).forEach(file => {
                if (checkFileSizeLimit(file, MAXIMUM_FILE_UPLOAD_SIZE)) {
                  this.uploadArticleAttachment(file);
                } else {
                  useAlert(
                    this.$t(
                      'HELP_CENTER.ARTICLE_EDITOR.FILE_UPLOAD.ERROR_FILE_SIZE',
                      { size: MAXIMUM_FILE_UPLOAD_SIZE }
                    )
                  );
                }
              });
              event.preventDefault();
            }
          },
        },
      });
    },
    handleKeyEvents() {},
    focusEditorInputField() {
      const { tr } = editorView.state;
      const selection = Selection.atEnd(tr.doc);

      editorView.dispatch(tr.setSelection(selection));
      editorView.focus();
    },
    emitOnChange() {
      this.$emit('update:modelValue', this.contentFromEditor());
      this.$emit('input', this.contentFromEditor());
    },
    onKeyup() {
      this.$emit('keyup');
    },
    onKeydown() {
      this.$emit('keydown');
    },
    onBlur() {
      this.$emit('blur');
    },
    onFocus() {
      this.$emit('focus');
    },
    checkSelection(editorState) {
      const { from, to } = editorState.selection;
      // Check if there's a selection (from and to are different)
      const hasSelection = from !== to;
      // If the selection state is the same as the previous state, do nothing
      if (hasSelection === this.isTextSelected) return;
      // Update the selection state
      this.isTextSelected = hasSelection;

      const { editor } = this.$refs;

      // Toggle the 'has-selection' class based on whether there's a selection
      editor.classList.toggle('has-selection', hasSelection);
      // If there's a selection, update the menubar position
      if (hasSelection) this.setMenubarPosition(editorState);
    },
    setMenubarPosition(editorState) {
      if (!editorState.selection) return;

      // Get the start and end positions of the selection
      const { from, to } = editorState.selection;
      const { editor } = this.$refs;
      // Get the editor's position relative to the viewport
      const { left: editorLeft, top: editorTop } =
        editor.getBoundingClientRect();

      // Get the editor's width
      const editorWidth = editor.offsetWidth;
      const menubarWidth = 480; // Menubar width (adjust as needed (px))

      // Get the end position of the selection
      const { bottom: endBottom, right: endRight } = editorView.coordsAtPos(to);
      // Get the start position of the selection
      const { left: startLeft } = editorView.coordsAtPos(from);

      // Calculate the top position for the menubar (10px below the selection)
      const top = endBottom - editorTop + 10;
      // Calculate the left position for the menubar
      // This centers the menubar on the selection while keeping it within the editor's bounds
      const left = Math.max(
        0,
        Math.min(
          (startLeft + endRight) / 2 - editorLeft,
          editorWidth - menubarWidth
        )
      );
      // Set the CSS custom properties for positioning the menubar
      editor.style.setProperty('--selection-top', `${top}px`);
      editor.style.setProperty('--selection-left', `${left}px`);
    },
  },
};
</script>

<template>
  <div>
    <div class="editor-root editor--article">
      <input ref="imageUploadInput" type="file" hidden @change="onFileChange" />
      <div ref="editor" />
    </div>
  </div>
</template>

<style lang="scss">
@import '@chatwoot/prosemirror-schema/src/styles/article.scss';

.ProseMirror-menubar-wrapper {
  display: flex;
  flex-direction: column;

  > .ProseMirror {
    padding: 0;
    word-break: break-word;
  }
}

.editor-root {
  position: relative;
  width: 100%;
}

.ProseMirror-woot-style {
  min-height: 5rem;
  max-height: 7.5rem;
  overflow: auto;
}
</style>
