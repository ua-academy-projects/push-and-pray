export const OVERVIEW_SIDEBAR_ENTRY = 'oilscope-overview';

export const OVERVIEW_PATH = '/';

export const overviewRoute = {
  path: OVERVIEW_PATH,
  exact: true,
  name: 'OilScope Overview',
  sidebar: OVERVIEW_SIDEBAR_ENTRY,
  useClusterURL: true,
};

export const overviewSidebarEntry = {
  parent: null,
  name: OVERVIEW_SIDEBAR_ENTRY,
  label: 'OilScope Overview',
  icon: 'mdi:gauge',
  url: OVERVIEW_PATH,
};
