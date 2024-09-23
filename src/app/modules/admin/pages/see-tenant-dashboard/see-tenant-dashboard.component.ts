import { ChangeDetectionStrategy, Component, AfterViewInit, ViewChildren, QueryList, ViewChild, OnInit } from '@angular/core';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatPaginator, MatPaginatorIntl, MatPaginatorModule } from '@angular/material/paginator';
import { MatSort, MatSortModule } from '@angular/material/sort';
import { MatTableDataSource, MatTableModule } from '@angular/material/table';
import { ActivatedRoute, Router } from '@angular/router';
import { MatCardModule } from '@angular/material/card';
import { MatInputModule } from '@angular/material/input';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatTooltipModule } from '@angular/material/tooltip';
import { CommonModule } from '@angular/common';
import { SupabaseService } from '../../../../services/supabase.service';


const OPTIONS: string[] = [
  'On', 'Off', 'Suspended'
];

@Component({
  selector: 'app-see-tenant-dashboard',
  standalone: true,
  imports: [MatCardModule, MatInputModule, MatFormFieldModule, MatTableModule, MatSortModule, MatPaginatorModule, MatButtonModule, MatIconModule, MatTooltipModule, CommonModule],
  templateUrl: './see-tenant-dashboard.component.html',
  styleUrls: ['./see-tenant-dashboard.component.scss'],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class SeeTenantDashboardComponent implements OnInit {
  id: any;
  user: any;
  users: any = [];
  monitored: any = [];
  IoTDevices: any = [];
  medicalDevices: any = [];

  displayedUsersColumns: string[] = ['name', 'email', 'role', 'actions'];
  dataSourceUsers: MatTableDataSource<any>;

  displayedSeniorCitizensColumns: string[] = ['name', 'gender', 'age', 'actions'];
  dataSourceSeniorCitizens: MatTableDataSource<any>;

  displayedDevicesIoTColumns: string[] = ['name', 'status', 'serialID', 'actions'];
  dataSourceDevicesIoT: MatTableDataSource<any>;

  displayedMedicalDevicesColumns: string[] = ['type', 'owner', 'status', 'lastMeasurement', 'lastMeasurementDate', 'actions'];
  dataSourceMedicalDevices: MatTableDataSource<any>;

  @ViewChild('usersPaginator') usersPaginator: MatPaginator;
  @ViewChild('usersSort') usersSort: MatSort;

  @ViewChild('seniorCitizensPaginator') seniorCitizensPaginator: MatPaginator;
  @ViewChild('seniorCitizensSort') seniorCitizensSort: MatSort;

  @ViewChild('devicesIoTPaginator') devicesIoTPaginator: MatPaginator;
  @ViewChild('devicesIoTSort') devicesIoTSort: MatSort;

  @ViewChild('medicalDevicesPaginator') medicalDevicesPaginator: MatPaginator;
  @ViewChild('medicalDevicesSort') medicalDevicesSort: MatSort;

  constructor(
    public _MatPaginatorIntl: MatPaginatorIntl,
    private _route: ActivatedRoute,
    private _supabaseService: SupabaseService,
  ) {
  }
  async ngOnInit() {
    this.user = await this._supabaseService.getUserSession();
    this.id = this._route.snapshot.paramMap.get('id');
    await this.getMembers(this.id, this.user.data.user.role);
    await this.getMonitored(this.id);
    await this.getIoTDevices(this.id);
    await this.getMedicalDevices(this.id);
  }


  /**
   * Function that allows the person to filter in the users table and display the data related to the filter
   */
  applyFilterUsers(event: Event) {
    const filterValue = (event.target as HTMLInputElement).value;
    this.dataSourceUsers.filter = filterValue.trim().toLowerCase();

    if (this.dataSourceUsers.paginator) {
      this.dataSourceUsers.paginator.firstPage();
    }
  }

  /**
   * Function that allows the person to filter in the senior citizens table and display the data related to the filter
   */
  applyFilterSeniorCitizens(event: Event) {
    const filterValue = (event.target as HTMLInputElement).value;
    this.dataSourceSeniorCitizens.filter = filterValue.trim().toLowerCase();

    if (this.dataSourceSeniorCitizens.paginator) {
      this.dataSourceSeniorCitizens.paginator.firstPage();
    }
  }

  /**
   * Function that allows the person to filter in the iot devices table and display the data related to the filter
   */
  applyFilterDevicesIoT(event: Event) {
    const filterValue = (event.target as HTMLInputElement).value;
    this.dataSourceDevicesIoT.filter = filterValue.trim().toLowerCase();

    if (this.dataSourceDevicesIoT.paginator) {
      this.dataSourceDevicesIoT.paginator.firstPage();
    }
  }

  /**
   * Function that allows the person to filter in the medical devices table and display the data related to the filter
   */
  applyFilterMedicalDevices(event: Event) {
    const filterValue = (event.target as HTMLInputElement).value;
    this.dataSourceMedicalDevices.filter = filterValue.trim().toLowerCase();

    if (this.dataSourceMedicalDevices.paginator) {
      this.dataSourceMedicalDevices.paginator.firstPage();
    }
  }


  /**
   * Function that gets the members of a tenant
   */
  private async getMembers(tenant_id: any, role: string) {
    try {
      if (role === "service_role") {
        const { data, error } = await this._supabaseService.getTenantMembersService(tenant_id);
        if (error) {
          throw new Error(`Error al obtener los miembros del tenant (service_role): ${error.message}`);
        }
        for (let i = 0; i < data.length; i++) {
          const member = data[i];
          const newMember = {
            name: member.firstname + ' ' + member.lastname,
            email: member.email,
            role: (member.tenant_role == "owner") ? "Dueño" : "Miembro",
          };
          this.users.push(newMember);
        }
      } else {
        const { data, error } = await this._supabaseService.getTenantMembers(tenant_id);
        if (error) {
          throw new Error(`Error al obtener los miembros del tenant: ${error.message}`);
        }
        for (let i = 0; i < data.length; i++) {
          const member = data[i];
          const newMember = {
            name: member.firstname + ' ' + member.lastname,
            email: member.email,
            role: (member.tenant_role == "owner") ? "Dueño" : "Miembro",
          };
          this.users.push(newMember);
        }

      }
      this.dataSourceUsers = new MatTableDataSource(this.users);
      this.dataSourceUsers.paginator = this.usersPaginator;
      this.dataSourceUsers.sort = this.usersSort;
      this.usersPaginator._intl.itemsPerPageLabel = 'Usuarios por página';

    } catch (error: any) {
      console.error('Error en getMembers:', error.message || error);
    }
  }

  /**
   * Function that returns the monitored data of a tenant
   */
  private async getMonitored(tenant_id: any) {
    try {
      const { data, error } = await this._supabaseService.getMonitoredPeople(tenant_id);
      if (error) {
        throw new Error(`Error al obtener los monitoreados del tenant ${error.message}`);
      }
      for (let i = 0; i < data.length; i++) {
        const monitored = data[i];
        const newMonitored = {
          name: monitored.first_name + ' ' + monitored.last_name,
          gender: (monitored.gender == "M") ? "Masculino" : "Femenino",
          age: monitored?.age ?? "No tiene dato",
        };
        this.monitored.push(newMonitored);
      }
      this.dataSourceSeniorCitizens = new MatTableDataSource(this.monitored);
      this.dataSourceSeniorCitizens.paginator = this.seniorCitizensPaginator;
      this.dataSourceSeniorCitizens.sort = this.seniorCitizensSort;
      this.seniorCitizensPaginator._intl.itemsPerPageLabel = 'Personas por página';

    } catch (error: any) {
      console.error('Error en getMonitored:', error.message || error);
    }
  }

  /**
   * Function that returns the IoT Devices a of a tenant
   */
  private async getIoTDevices(tenant_id: any) {
    try {
      const { data, error } = await this._supabaseService.getIoTDevicesByTenant(tenant_id);
      if (error) {
        throw new Error(`Error al obtener los dispositivos IoT del tenant ${error.message}`);
      }
      for (let i = 0; i < data.length; i++) {
        const IoTDevice = data[i];
        const newIoTDevice = {
          name: IoTDevice.name,
          status: OPTIONS[Math.floor(Math.random() * OPTIONS.length)],
          serialID: IoTDevice.serial_number,
        };
        this.IoTDevices.push(newIoTDevice);
      }
      this.dataSourceDevicesIoT = new MatTableDataSource(this.IoTDevices);
      this.dataSourceDevicesIoT.paginator = this.devicesIoTPaginator;
      this.dataSourceDevicesIoT.sort = this.devicesIoTSort;
      this.devicesIoTPaginator._intl.itemsPerPageLabel = 'Dispositivos IoT por página';

    } catch (error: any) {
      console.error('Error en getMonitored:', error.message || error);
    }
  }

  /**
   * Function that return the medical devices a of a tenant
   */
  private async getMedicalDevices(tenant_id: any) {
    try {
      const { data, error } = await this._supabaseService.getMedicalDevicesByTenant(tenant_id);
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
        this.medicalDevices = this.getUniqueMedicalDevices(allMedicalDevices);

      }
      this.dataSourceMedicalDevices = new MatTableDataSource(this.medicalDevices);
      this.dataSourceMedicalDevices.paginator = this.medicalDevicesPaginator;
      this.dataSourceMedicalDevices.sort = this.medicalDevicesSort;
      this.medicalDevicesPaginator._intl.itemsPerPageLabel = 'Dispositivos médicos por página';

    } catch (error: any) {
      console.error('Error en getMedicalDevices:', error.message || error);
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