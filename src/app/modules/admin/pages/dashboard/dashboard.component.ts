import { ChangeDetectionStrategy, Component, AfterViewInit, ViewChild, inject } from '@angular/core';
import { MatCardModule } from '@angular/material/card';
import { MatInputModule } from '@angular/material/input';
import { MatPaginator, MatPaginatorIntl, MatPaginatorModule } from '@angular/material/paginator';
import { MatSort, MatSortModule } from '@angular/material/sort';
import { MatTableDataSource, MatTableModule } from '@angular/material/table';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatDialog } from '@angular/material/dialog';
import { DialogCreateTenantComponent } from '../../components/dialog-create-tenant/dialog-create-tenant.component';
import { MatTooltipModule } from '@angular/material/tooltip';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { SupabaseService } from '../../../../services/supabase.service';
import { ChangeDetectorRef } from '@angular/core';


const OPTIONS: string[] = [
  'On', 'Off', 'Suspended'
];

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [MatCardModule, MatInputModule, MatFormFieldModule, MatInputModule, MatTableModule, MatSortModule, MatPaginatorModule, MatButtonModule, MatIconModule, MatTooltipModule, CommonModule],
  templateUrl: './dashboard.component.html',
  styleUrl: './dashboard.component.scss',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class DashboardComponent {
  accounts: number;
  users: number;
  monitored: number;
  devicesIoT: number;
  medicalDevices: number = 0;
  dialog = inject(MatDialog);
  tenants: any[];
  dataTable: any[] = [];
  id: any;
  user: any;

  displayedColumns: string[] = ['owner', 'users', 'devices', 'deviceIoT', 'status', 'actions'];
  dataSource: MatTableDataSource<any>;

  @ViewChild(MatPaginator) paginator: MatPaginator;
  @ViewChild(MatSort) sort: MatSort;

  constructor(
    public _MatPaginatorIntl: MatPaginatorIntl,
    private _router: Router,
    private _supabaseService: SupabaseService,
    private cdr: ChangeDetectorRef
  ) { }

  /**
   * Function that brings information about tenants
   */
  async ngOnInit() {
    this.user = await this._supabaseService.getUserSession();
    if (this.user.data.user.role === "service_role") {
      await this.getAllTenants();
    } else {
      await this.getUserTenants();
    }
    this.accounts = this.tenants.length;
    this.getTenantMembers(this.tenants);
    this.getMonitoredPeople(this.tenants);
    this.getIoTDevicesByTenant(this.tenants);
    this.createDataForTable(this.tenants);
    this.getMedicalDevices(this.tenants)
    this.cdr.detectChanges();
  }

  /**
   * Function that allows the person to filter in the table and display the data related to the filter
   */
  public applyFilter(event: Event) {
    const filterValue = (event.target as HTMLInputElement).value;
    this.dataSource.filter = filterValue.trim().toLowerCase();

    if (this.dataSource.paginator) {
      this.dataSource.paginator.firstPage();
    }
  }

  /**
   * Function that returns all the tenants of the database
   */
  private async getAllTenants() {
    try {
      const { data, error } = await this._supabaseService.getAllTenants();

      if (error) {
        console.error("Error al obtener todos los tenants:", error.message);
        return;
      }
      this.tenants = data;
    } catch (e) {
      console.error("Ocurrió un error inesperado:", e);
    }
  }

  /**
  * Function that returns the user's tenants
  */
  private async getUserTenants() {
    try {
      const { data, error } = await this._supabaseService.getTenants();

      if (error) {
        console.error("Error al obtener los tenants del usuario:", error.message);
        return;
      }
      this.tenants = data;
    } catch (e) {
      console.error("Ocurrió un error inesperado:", e);
    }
  }

  /**
   * Function that returns the members of the tenants
   */
  private async getTenantMembers(tenants: any[]) {
    if (this.user.data.user.role === "service_role") {
      this.users = 0;

      const promises = tenants.map(async (tenant: any) => {
        const { data, error } = await this._supabaseService.getTenantMembersService(tenant.tenant_id);

        if (error) {
          console.error(`Error al obtener los usuarios monitorizados para tenant ${tenant.tenant_id}:`, error);
          return 0;
        }
        return data?.length ?? 0;
      });

      const results = await Promise.all(promises);
      this.users = results.reduce((acc, curr) => acc + curr, 0);
      this.cdr.detectChanges();
    }
    else {
      try {
        const tenantId = this.user.data.user.id;
        const { data, error } = await this._supabaseService.getTenantMembers(tenantId);

        if (error) {
          console.error('Error al obtener los miembros del tenant:', error.message);
          throw error;
        }
        this.users = data.length;
        this.cdr.detectChanges();
      } catch (e) {
        console.error('Error en la función getTenantMembers:', e);
        throw e;
      }
    }

  }

  /**
   * Function that returns the people who are being monitored in that tenant
   */
  private async getMonitoredPeople(tenants: any) {
    if (this.user.data.user.role === "service_role") {
      this.monitored = 0;

      const promises = tenants.map(async (tenant: any) => {
        const { data, error } = await this._supabaseService.getMonitoredPeople(tenant.tenant_id);

        if (error) {
          console.error(`Error al obtener los usuarios monitorizados para tenant ${tenant.tenant_id}:`, error);
          return 0;
        }
        return data?.length ?? 0;
      });

      const results = await Promise.all(promises);
      this.monitored = results.reduce((acc, curr) => acc + curr, 0);
      this.cdr.detectChanges();
    } else {
      try {
        const tenantId = this.user.data.user.id;
        const { data, error } = await this._supabaseService.getMonitoredPeople(tenantId);

        if (error) {
          console.error('Error al obtener los usuarios monitorizados:', error.message);
          throw error;
        }
        this.monitored = data.length;
        this.cdr.detectChanges();
      } catch (e) {
        console.error('Error en la función getMonitoredPeople:', e);
        throw e;
      }
    }
  }

  /**
   * Function that returns the IoT devices of the tenant or tenants
   */
  private async getIoTDevicesByTenant(tenants: any) {
    if (this.user.data.user.role === "service_role") {
      this.devicesIoT = 0;

      const promises = tenants.map(async (tenant: any) => {
        const { data, error } = await this._supabaseService.getIoTDevicesByTenant(tenant.tenant_id);

        if (error) {
          console.error(`Error al obtener los dispositivos IoT para cada tenant ${tenant.tenant_id}:`, error);
          return 0;
        }
        return data?.length ?? 0;
      });

      const results = await Promise.all(promises);
      this.devicesIoT = results.reduce((acc, curr) => acc + curr, 0);

      this.cdr.detectChanges();
    } else {
      try {
        const tenantId = this.user.data.user.id;
        const { data, error } = await this._supabaseService.getIoTDevicesByTenant(tenantId);

        if (error) {
          console.error('Error al obtener los dispositivos IoT del tenant:', error.message);
          throw error;
        }
        this.devicesIoT = data.length;
        this.cdr.detectChanges();
      } catch (e) {
        console.error('Error en la función getIoTDevicesByTenant:', e);
        throw e;
      }
    }
  }

  /**
   * Function that redirects to view the information of a specific tenant
   */
  public seeDetails(id: string) {
    this._router.navigate(['/admin/see-tenant-dashboard', id]);
  }

  /**
   * Function that removes a tenant from the table
   */
  public deleteTenant(id: string) {
    const filteredData = this.dataSource.data.filter((element: any) => element.id !== id);
    this.dataSource.data = filteredData;
  }

  /**
   * Function that opens the dialog to create a tenant
   */
  public createTenant() {
    this.dialog.open(DialogCreateTenantComponent, {
      width: '30%',
      height: 'auto',
    });
  }

  /**
   * Function that adds the data to display in the table
   */
  private async createDataForTable(tenants: any) {
    const promises = tenants.map(async (tenant: any) => {
      const id = tenant.tenant_id;
      const account = tenant.slug;
      const devicesIoT = (await this._supabaseService.getIoTDevicesByTenant(id)).data;
      const devicesIoTAmount = devicesIoT?.length ?? 0;
      const devicesIotStatus = OPTIONS[Math.floor(Math.random() * OPTIONS.length)]
      const status = OPTIONS[Math.floor(Math.random() * OPTIONS.length)]
      if (this.user.data.user.role === "service_role") {
        const users = await (await this._supabaseService.getTenantMembersService(id)).data;
        const usersAmount = users.length;
        const ownerData = users.filter((item: any) => item.tenant_role === 'owner');
        const ownerName = ownerData[0].firstname + ' ' + ownerData[0].lastname;
        const newTenant = {
          id: id,
          account: account,
          owner: ownerName,
          users: usersAmount,
          devices: devicesIoTAmount,
          deviceIoT: devicesIotStatus,
          status: status
        }
        this.dataTable.push(newTenant);
      } else {
        const users = await (await this._supabaseService.getTenantMembers(id)).data;
        const usersAmount = users.length;
        const ownerData = users.filter((item: any) => item.tenant_role === 'owner');
        const ownerName = ownerData[0].firstname + ' ' + ownerData[0].lastname;
        const newTenant = {
          id: id,
          account: account,
          owner: ownerName,
          users: usersAmount,
          devices: devicesIoTAmount,
          deviceIoT: devicesIotStatus,
          status: status
        }
        this.dataTable.push(newTenant);
      }
    });
    await Promise.all(promises);
    this.dataSource = new MatTableDataSource(this.dataTable);
    this.dataSource.paginator = this.paginator;
    this.dataSource.sort = this.sort;
    if (this.paginator._intl) {
      this.paginator._intl.itemsPerPageLabel = "Cuentas por página";
    }
  }

  /**
   * Function that return the medical devices a of a tenant
   */
  private async getMedicalDevices(tenants: any) {
    if (this.user.data.user.role === "service_role") {
      tenants.map(async (tenant: any) => {
        try {
          const { data, error } = await this._supabaseService.getMedicalDevicesByTenant(tenant.tenant_id);
          if (error) {
            throw new Error(`Error al obtener los dispositivos IoT del tenant ${error.message}`);
          }
          let medicalDevices2;
          let allMedicalDevices = [];
          (data != null) ? medicalDevices2 = data : medicalDevices2 = [];

          for (let i = 0; i < medicalDevices2.length; i++) {
            const medicalDevice = medicalDevices2[i];
            const newMedicalDevice = {
              id: medicalDevice.medical_device_id,
              type: medicalDevice.device_type_name,
              status: OPTIONS[Math.floor(Math.random() * OPTIONS.length)],
              lastMeasurement: medicalDevice.last_measurement,
              lastMeasurementDate: medicalDevice.measurement_date,
              name: medicalDevice.first_name + ' ' + medicalDevice.last_name,
            };
            allMedicalDevices.push(newMedicalDevice);
          }
          this.medicalDevices += this.getUniqueMedicalDevices(allMedicalDevices).length;
        } catch (error: any) {
          console.error('Error en getMedicalDevices:', error.message || error);
        }
      })

    } else {
      try {
        const { data, error } = await this._supabaseService.getMedicalDevicesByTenant(tenants[0].tenant_id);
        if (error) {
          throw new Error(`Error al obtener los dispositivos IoT del tenant ${error.message}`);
        }
        let medicalDevices;
        let allMedicalDevices = [];
        (data != null) ? medicalDevices = data : medicalDevices = [];

        for (let i = 0; i < medicalDevices.length; i++) {
          const medicalDevice = medicalDevices[i];
          const newMedicalDevice = {
            id: medicalDevice.medical_device_id,
            type: medicalDevice.device_type_name,
            status: OPTIONS[Math.floor(Math.random() * OPTIONS.length)],
            lastMeasurement: medicalDevice.last_measurement,
            lastMeasurementDate: medicalDevice.measurement_date,
            name: medicalDevice.first_name + ' ' + medicalDevice.last_name,
          };
          allMedicalDevices.push(newMedicalDevice);
          this.medicalDevices = this.getUniqueMedicalDevices(allMedicalDevices).length;

        }
      } catch (error: any) {
        console.error('Error en getMedicalDevices:', error.message || error);
      }
    }


  }

  /**
   * Function that returns an array with unique values
   */
  private getUniqueMedicalDevices(medicalDevices: any) {
    const uniqueObjectsMap = new Map<string, any>();

    medicalDevices.forEach((medicalDevice: any) => {
      const existingObj = uniqueObjectsMap.get(medicalDevice.id);

      if (existingObj) {
        const currentDate = new Date(medicalDevice.lastMeasurementDate);
        const existingDate = new Date(existingObj.lastMeasurementDate);

        if (currentDate > existingDate) {
          uniqueObjectsMap.set(medicalDevice.id, medicalDevice);
        }
      } else {
        uniqueObjectsMap.set(medicalDevice.id, medicalDevice);
      }
    });

    return Array.from(uniqueObjectsMap.values());
  }
}