import { frontendURL } from 'dashboard/helper/URLHelper.js';
import {
  ROLES,
  CONVERSATION_PERMISSIONS,
} from 'dashboard/constants/permissions.js';

import TicketsPageLayout from './TicketsPageLayout.vue';
import TicketsIndexPage from './TicketsIndexPage.vue';
import TicketsNewPage from './TicketsNewPage.vue';
import TicketsShowPage from './TicketsShowPage.vue';

const meta = {
  permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
};

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/tickets'),
      component: TicketsPageLayout,
      children: [
        {
          path: '',
          name: 'tickets_dashboard_index',
          meta,
          component: TicketsIndexPage,
        },
        {
          path: 'new',
          name: 'tickets_dashboard_new',
          meta,
          component: TicketsNewPage,
        },
        {
          path: ':displayId',
          name: 'tickets_dashboard_show',
          meta,
          component: TicketsShowPage,
        },
      ],
    },
  ],
};
